"""HomeStack — App registry / catalog.

Manages the local clone of the homestack-apps repository.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from homestack import core, db
from homestack.yaml_parser import yaml_get, load_yaml


# Default repo URL
_DEFAULT_REPO = "https://github.com/filippvizvary/homestack-apps.git"


def _repo_url() -> str:
    """Resolve the catalog repo URL from environment or config."""
    url = os.environ.get("HOMESTACK_APPS_REPO")
    if url:
        return url
    # Try to read from homestack.env
    if core.CONFIG_FILE.is_file():
        for line in core.CONFIG_FILE.read_text().splitlines():
            if line.startswith("HOMESTACK_APPS_REPO="):
                return line.split("=", 1)[1].strip()
    return _DEFAULT_REPO


def registry_sync() -> bool:
    """Clone or pull the catalog repo. Returns True on success."""
    cache_dir = core.CACHE_DIR

    # Ensure git trusts the cache directory
    subprocess.run(
        ["git", "config", "--global", "--add", "safe.directory", str(cache_dir)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    if (cache_dir / ".git").is_dir():
        core.step("Updating app catalog")
        r = subprocess.run(
            ["git", "-C", str(cache_dir), "pull", "--quiet"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            core.success("App catalog updated")
        else:
            core.warn("Failed to update catalog, using cached version")
            return False
    else:
        core.step("Downloading app catalog")
        cache_dir.parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(
            ["git", "clone", "--depth", "1", _repo_url(), str(cache_dir)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            core.success("App catalog downloaded")
        else:
            core.error(f"Failed to download app catalog from {_repo_url()}")
            return False

    # Update catalog versions in database for installed apps
    _update_catalog_versions()
    return True


def _update_catalog_versions() -> None:
    """Sync catalog version numbers into the DB for installed apps."""
    if not core.DB_FILE.is_file():
        return
    apps_dir = core.APPS_DIR
    if not apps_dir.is_dir():
        return
    for d in apps_dir.iterdir():
        app_yaml = d / "app.yaml"
        if not app_yaml.is_file():
            continue
        name = d.name
        version = yaml_get(str(app_yaml), "version")
        if db.db_is_installed(name):
            db.db_set_catalog_version(name, version)


def registry_ensure() -> bool:
    """Ensure the catalog is available locally. Sync if missing."""
    if not core.APPS_DIR.is_dir():
        return registry_sync()
    return True


def registry_list() -> list[dict]:
    """List all apps in the catalog.

    Returns list of dicts with keys: name, display_name, description, category, port.
    """
    registry_ensure()
    result: list[dict] = []
    apps_dir = core.APPS_DIR
    if not apps_dir.is_dir():
        return result
    for d in sorted(apps_dir.iterdir()):
        app_yaml = d / "app.yaml"
        if not app_yaml.is_file():
            continue
        data = load_yaml(str(app_yaml))
        result.append({
            "name": str(data.get("name", d.name)),
            "display_name": str(data.get("display_name", d.name)),
            "description": str(data.get("description", "")),
            "category": str(data.get("category", "")),
            "port": str(data.get("port", "")),
        })
    return result


def registry_find(app_name: str) -> str:
    """Find an app directory by name.

    Returns the absolute path string, or empty string if not found.
    Supports case-insensitive fallback.
    """
    registry_ensure()
    apps_dir = core.APPS_DIR

    # Exact match
    candidate = apps_dir / app_name
    if candidate.is_dir() and (candidate / "app.yaml").is_file():
        return str(candidate)

    # Case-insensitive fallback
    lower = app_name.lower()
    candidate = apps_dir / lower
    if candidate.is_dir() and (candidate / "app.yaml").is_file():
        return str(candidate)

    return ""


def registry_search(query: str) -> list[dict]:
    """Search catalog apps by substring (case-insensitive).

    Matches against name, display_name, description, and category.
    """
    registry_ensure()
    query_lower = query.lower()
    result: list[dict] = []
    apps_dir = core.APPS_DIR
    if not apps_dir.is_dir():
        return result
    for d in sorted(apps_dir.iterdir()):
        app_yaml = d / "app.yaml"
        if not app_yaml.is_file():
            continue
        data = load_yaml(str(app_yaml))
        name = str(data.get("name", d.name))
        display = str(data.get("display_name", ""))
        desc = str(data.get("description", ""))
        cat = str(data.get("category", ""))
        port = str(data.get("port", ""))
        haystack = f"{name} {display} {desc} {cat}".lower()
        if query_lower in haystack:
            result.append({
                "name": name,
                "display_name": display,
                "description": desc,
                "category": cat,
                "port": port,
            })
    return result
