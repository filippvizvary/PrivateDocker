"""homestack backup [app]"""

from __future__ import annotations

import os
import sys
import tarfile
from datetime import datetime
from pathlib import Path

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get, yaml_get_array

KEEP_LAST = 5


@click.command("backup")
@click.argument("app_name", required=False, default=None)
def cmd_backup(app_name: str | None) -> None:
    """Backup all or a specific app's data."""

    with core.homestack_lock():
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")

        click.echo(click.style(
            f"=== HomeStack Backup — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===",
            fg="blue", bold=True,
        ))
        click.echo()

        if app_name:
            _backup_app(app_name, ts)
        else:
            apps = core.get_installed_apps()
            if not apps:
                core.warn("No apps installed.")
                return
            for app in apps:
                _backup_app(app, ts)

        click.echo()
        core.success("Backup complete")


def _backup_app(app_name: str, timestamp: str) -> None:
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        return

    install_dir = core.INSTALLED_DIR / app_name
    app_yaml = install_dir / "app.yaml"
    display_name = yaml_get(str(app_yaml), "display_name")

    dest = core.BACKUPS_DIR / app_name
    core.ensure_dir(dest)

    # Backup config files
    core.step(f"Backing up {display_name} config")
    config_archive = dest / f"{app_name}_config_{timestamp}.tar.gz"
    with tarfile.open(config_archive, "w:gz") as tar:
        for f in install_dir.iterdir():
            tar.add(f, arcname=f.name)
    config_size = config_archive.stat().st_size
    db.db_record_backup(app_name, str(config_archive), config_size, "config")
    core.success(f"{display_name} config → {config_archive.name}")

    # Backup AppData
    appdata_dirs = yaml_get_array(str(app_yaml), "appdata_dirs")
    if not appdata_dirs:
        core.warn(f"{display_name}: no AppData directories defined, skipping data backup")
        db.db_log_action("backup", app_name, "Config backup only (no appdata)")
        return

    # Check backup strategy (bug fix: default is "live", not "stop")
    backup_strategy = yaml_get(str(app_yaml), "backup_strategy") or "live"

    was_running = False
    if backup_strategy == "stop":
        # Check if containers are running
        try:
            result = core.compose_cmd(
                install_dir, "ps", "--quiet",
                capture=True, check=False, quiet_err=True,
            )
            if result.stdout and result.stdout.strip():
                was_running = True
                core.step(f"Stopping {display_name} for safe backup")
                core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
        except Exception:
            pass

    # Archive all appdata dirs
    data_archive = dest / f"{app_name}_data_{timestamp}.tar.gz"
    has_data = False
    valid_dirs: list[str] = []

    for d in appdata_dirs:
        if not core.validate_path_component(d):
            continue
        src = core.APPDATA_DIR / d
        if src.is_dir():
            valid_dirs.append(d)
            has_data = True
        else:
            core.warn(f"{display_name}: {src} does not exist, skipping")

    if has_data:
        core.step(f"Backing up {display_name} data")
        with tarfile.open(data_archive, "w:gz") as tar:
            for d in valid_dirs:
                tar.add(core.APPDATA_DIR / d, arcname=d)
        data_size = data_archive.stat().st_size
        db.db_record_backup(app_name, str(data_archive), data_size, "data")
        core.success(f"{display_name} data → {data_archive.name}")

    # Restart if we stopped it
    if was_running:
        core.step(f"Restarting {display_name}")
        networks = yaml_get_array(str(app_yaml), "networks")
        for network in networks:
            core.ensure_network(network)
        core.compose_cmd(install_dir, "up", "-d")
        core.success(f"{display_name} restarted")

    # Rotate: keep only the last N backups per type (files AND DB records)
    _rotate_backups(app_name, dest)

    db.db_log_action("backup", app_name, "Backup completed: config + data")


def _rotate_backups(app_name: str, dest: Path) -> None:
    """Rotate old backups, deleting both files and DB records."""
    for backup_type in ("config", "data"):
        pattern = f"{app_name}_{backup_type}_*.tar.gz"
        files = sorted(dest.glob(pattern), key=lambda f: f.stat().st_mtime, reverse=True)
        for old_file in files[KEEP_LAST:]:
            old_file.unlink(missing_ok=True)

        # Also clean up DB records for files that no longer exist
        backups = db.db_list_backups(app_name)
        for b in backups:
            if b["type"] == backup_type and not Path(b["path"]).is_file():
                db.db_remove_backup(b["id"])
