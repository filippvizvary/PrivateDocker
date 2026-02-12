"""Shared pytest fixtures for HomeStack tests."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

import pytest


TESTS_DIR = Path(__file__).parent
PROJECT_DIR = TESTS_DIR.parent
FIXTURES_DIR = TESTS_DIR / "fixtures"


@pytest.fixture()
def tmp_homestack(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Create a temporary HomeStack environment.

    Sets HOMESTACK_DIR env var and refreshes core paths.
    Returns the root directory.
    """
    hs = tmp_path / "homestack"
    hs.mkdir()

    # Standard layout
    (hs / "installed").mkdir()
    (hs / "AppData").mkdir()
    (hs / "Backups").mkdir()
    (hs / "Media").mkdir()
    (hs / "config").mkdir()
    (hs / ".cache" / "homestack-apps" / "apps").mkdir(parents=True)

    # Minimal homestack.env
    env_file = hs / "config" / "homestack.env"
    env_file.write_text(
        f"HOMESTACK_DIR={hs}\n"
        f"APPDATA={hs / 'AppData'}\n"
        f"BACKUPS={hs / 'Backups'}\n"
        f"MEDIA={hs / 'Media'}\n"
        "TZ=UTC\n"
        "PUID=1000\n"
        "PGID=1000\n"
        "DOCKER_USER=1000:1000\n"
        "HOMESTACK_APPS_REPO=https://github.com/filippvizvary/homestack-apps.git\n"
    )

    monkeypatch.setenv("HOMESTACK_DIR", str(hs))

    # Refresh core paths
    from homestack import core
    core.refresh_paths()

    yield hs

    # Cleanup happens automatically via tmp_path


@pytest.fixture()
def db_init(tmp_homestack: Path):
    """Initialise the database in the temp env."""
    from homestack import db
    db.db_init()
    return tmp_homestack


@pytest.fixture()
def fixture_catalog(tmp_homestack: Path):
    """Copy test fixture catalog into the temp env."""
    dest = tmp_homestack / ".cache" / "homestack-apps" / "apps"
    src = FIXTURES_DIR / "catalog" / "apps"
    if src.is_dir():
        for app_dir in src.iterdir():
            if app_dir.is_dir():
                shutil.copytree(app_dir, dest / app_dir.name)
    return dest


def create_fixture_app(
    apps_dir: Path,
    name: str,
    port: int = 18080,
    priority: int = 50,
    secrets: str = "",
    networks: str = "[]",
    appdata_dirs: str | None = None,
    media_dirs: str = "[]",
) -> Path:
    """Create a fixture app in the given apps directory."""
    app_dir = apps_dir / name
    app_dir.mkdir(parents=True, exist_ok=True)

    if appdata_dirs is None:
        appdata_dirs = f"[{name}]"

    app_yaml = f"""\
name: {name}
display_name: {name.title()}
description: Test app {name}
version: 1.0.0
category: other
port: {port}
priority: {priority}
networks: {networks}
appdata_dirs: {appdata_dirs}
media_dirs: {media_dirs}
{secrets}
"""
    (app_dir / "app.yaml").write_text(app_yaml)

    compose = f"""\
name: {name}
services:
  {name}:
    image: ${{{name.upper()}_SERVER}}
    container_name: {name}
    ports:
      - {port}:80
    volumes:
      - ${{APPDATA}}/{name}:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s
"""
    (app_dir / "compose.yaml").write_text(compose)

    config_env = f"{name.upper()}_SERVER=nginx:1.27-alpine\n"
    (app_dir / "config.env").write_text(config_env)

    return app_dir


def mock_install_app(
    tmp_homestack: Path,
    name: str,
    version: str = "1.0.0",
    apps_dir: Path | None = None,
) -> Path:
    """Install a fixture app without Docker (DB + filesystem only)."""
    from homestack import db
    from homestack.yaml_parser import yaml_get

    install_dir = tmp_homestack / "installed" / name
    install_dir.mkdir(parents=True, exist_ok=True)

    if apps_dir is None:
        apps_dir = tmp_homestack / ".cache" / "homestack-apps" / "apps"

    src = apps_dir / name
    if src.is_dir():
        for f in ("app.yaml", "compose.yaml", "config.env"):
            src_f = src / f
            if src_f.is_file():
                shutil.copy2(src_f, install_dir / f)

    # Create empty secrets.env
    secrets = install_dir / "secrets.env"
    secrets.write_text("# No secrets\n")
    secrets.chmod(0o600)

    # Create AppData directory
    (tmp_homestack / "AppData" / name).mkdir(parents=True, exist_ok=True)

    # Add DB record
    db.db_set_installed(name, version)

    return install_dir
