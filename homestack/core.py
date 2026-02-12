"""HomeStack — Core utilities, paths, logging, locking, and Docker Compose wrapper."""

from __future__ import annotations

import fcntl
import os
import socket
import subprocess
import sys
from pathlib import Path

import click
import yaml


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

def _resolve_homestack_dir() -> Path:
    """Resolve HOMESTACK_DIR from environment or script location."""
    env = os.environ.get("HOMESTACK_DIR")
    if env:
        return Path(env)
    # Fall back to grandparent of this file (homestack/ package is inside repo root)
    return Path(__file__).resolve().parent.parent


HOMESTACK_DIR: Path = _resolve_homestack_dir()
INSTALLED_DIR: Path = HOMESTACK_DIR / "installed"
CONFIG_DIR: Path = HOMESTACK_DIR / "config"
CONFIG_FILE: Path = CONFIG_DIR / "homestack.env"
APPDATA_DIR: Path = HOMESTACK_DIR / "AppData"
BACKUPS_DIR: Path = HOMESTACK_DIR / "Backups"
MEDIA_DIR: Path = HOMESTACK_DIR / "Media"
DB_FILE: Path = HOMESTACK_DIR / "homestack.db"
LOCK_FILE: Path = HOMESTACK_DIR / ".lock"
CACHE_DIR: Path = HOMESTACK_DIR / ".cache" / "homestack-apps"
APPS_DIR: Path = CACHE_DIR / "apps"


def refresh_paths() -> None:
    """Re-derive all paths from the current HOMESTACK_DIR value.

    Useful after tests override ``HOMESTACK_DIR``."""
    global HOMESTACK_DIR, INSTALLED_DIR, CONFIG_DIR, CONFIG_FILE
    global APPDATA_DIR, BACKUPS_DIR, MEDIA_DIR, DB_FILE, LOCK_FILE
    global CACHE_DIR, APPS_DIR

    HOMESTACK_DIR = _resolve_homestack_dir()
    INSTALLED_DIR = HOMESTACK_DIR / "installed"
    CONFIG_DIR = HOMESTACK_DIR / "config"
    CONFIG_FILE = CONFIG_DIR / "homestack.env"
    APPDATA_DIR = HOMESTACK_DIR / "AppData"
    BACKUPS_DIR = HOMESTACK_DIR / "Backups"
    MEDIA_DIR = HOMESTACK_DIR / "Media"
    DB_FILE = HOMESTACK_DIR / "homestack.db"
    LOCK_FILE = HOMESTACK_DIR / ".lock"
    CACHE_DIR = HOMESTACK_DIR / ".cache" / "homestack-apps"
    APPS_DIR = CACHE_DIR / "apps"


# ---------------------------------------------------------------------------
# Logging helpers  (match the Bash [*] [✓] [!] [✗] format)
# ---------------------------------------------------------------------------

def step(msg: str) -> None:
    click.echo(click.style(f"[*] {msg}...", fg="blue", bold=True))

def success(msg: str) -> None:
    click.echo(click.style(f"[✓] {msg}", fg="green", bold=True))

def warn(msg: str) -> None:
    click.echo(click.style(f"[!] {msg}", fg="yellow"))

def error(msg: str) -> None:
    click.echo(click.style(f"[✗] {msg}", fg="red", bold=True), err=True)


# ---------------------------------------------------------------------------
# Locking (flock-based, same semantics as the Bash version)
# ---------------------------------------------------------------------------

_lock_fd: int | None = None


def acquire_lock() -> None:
    """Acquire a non-blocking file lock.  Exits with error if already held."""
    global _lock_fd
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    _lock_fd = os.open(str(LOCK_FILE), os.O_WRONLY | os.O_CREAT, 0o644)
    try:
        fcntl.flock(_lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        error(f"Another homestack process is running. If this is wrong, remove {LOCK_FILE}")
        sys.exit(1)


def release_lock() -> None:
    """Release the file lock."""
    global _lock_fd
    if _lock_fd is not None:
        try:
            fcntl.flock(_lock_fd, fcntl.LOCK_UN)
            os.close(_lock_fd)
        except OSError:
            pass
        _lock_fd = None
    try:
        LOCK_FILE.unlink(missing_ok=True)
    except OSError:
        pass


class homestack_lock:
    """Context manager for file locking."""

    def __enter__(self) -> None:
        acquire_lock()

    def __exit__(self, *_exc: object) -> None:
        release_lock()


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def validate_path_component(name: str) -> bool:
    """Reject empty strings, or names containing ``/`` or ``..`` (path traversal)."""
    if not name or "/" in name or ".." in name:
        error(f"Invalid path component: {name!r} (path traversal not allowed)")
        return False
    return True


def check_port_available(port: int) -> bool:
    """Return True if the TCP *port* is not in use on localhost."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) != 0


# ---------------------------------------------------------------------------
# Docker Compose wrapper
# ---------------------------------------------------------------------------

def compose_cmd(app_dir: str | Path, *args: str, capture: bool = False,
                check: bool = True, quiet_err: bool = False) -> subprocess.CompletedProcess:
    """Run ``docker compose`` with stacked ``--env-file`` flags.

    Parameters
    ----------
    app_dir:
        Directory containing *compose.yaml* for the app.
    args:
        Additional arguments forwarded to ``docker compose``.
    capture:
        If True, capture stdout/stderr instead of printing to terminal.
    check:
        If True (default), raise on non-zero exit.
    quiet_err:
        If True, suppress stderr.
    """
    app_dir = Path(app_dir)
    compose_file = app_dir / "compose.yaml"

    if not compose_file.is_file():
        error(f"compose.yaml not found in {app_dir}")
        raise FileNotFoundError(compose_file)

    env_flags: list[str] = ["--env-file", str(CONFIG_FILE)]
    config_env = app_dir / "config.env"
    if config_env.is_file():
        env_flags += ["--env-file", str(config_env)]
    secrets_env = app_dir / "secrets.env"
    if secrets_env.is_file():
        env_flags += ["--env-file", str(secrets_env)]

    cmd = ["docker", "compose", "-f", str(compose_file)] + env_flags + list(args)

    stderr_dest = subprocess.DEVNULL if quiet_err else (subprocess.PIPE if capture else None)
    stdout_dest = subprocess.PIPE if capture else None

    return subprocess.run(
        cmd,
        stdout=stdout_dest,
        stderr=stderr_dest,
        text=True,
        check=check,
    )


# ---------------------------------------------------------------------------
# App discovery
# ---------------------------------------------------------------------------

def get_installed_apps() -> list[str]:
    """Return installed app names sorted by priority (lower first)."""
    apps: list[tuple[int, str]] = []
    if not INSTALLED_DIR.is_dir():
        return []
    for d in sorted(INSTALLED_DIR.iterdir()):
        app_yaml = d / "app.yaml"
        if d.is_dir() and app_yaml.is_file():
            with open(app_yaml) as f:
                data = yaml.safe_load(f) or {}
            priority = int(data.get("priority", 50))
            apps.append((priority, d.name))
    apps.sort(key=lambda x: x[0])
    return [name for _, name in apps]


def is_installed(app_name: str) -> bool:
    """Check if an app is installed (directory + app.yaml exist)."""
    d = INSTALLED_DIR / app_name
    return d.is_dir() and (d / "app.yaml").is_file()


# ---------------------------------------------------------------------------
# Network / directory helpers
# ---------------------------------------------------------------------------

def ensure_network(name: str) -> None:
    """Create a Docker network if it doesn't exist."""
    r = subprocess.run(
        ["docker", "network", "inspect", name],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if r.returncode != 0:
        subprocess.run(
            ["docker", "network", "create", name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        success(f"Created Docker network '{name}'")


def ensure_dir(path: str | Path) -> None:
    """Create directory (including parents) if it doesn't exist."""
    Path(path).mkdir(parents=True, exist_ok=True)
