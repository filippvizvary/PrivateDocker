"""homestack restore <app>"""

from __future__ import annotations

import tarfile
from pathlib import Path

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get, yaml_get_array


@click.command("restore")
@click.argument("app_name")
def cmd_restore(app_name: str) -> None:
    """Restore an app from a previous backup."""

    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        click.echo(f"  Install it first with: homestack install {app_name}")
        raise SystemExit(1)

    with core.homestack_lock():
        install_dir = core.INSTALLED_DIR / app_name
        app_yaml = install_dir / "app.yaml"
        display_name = yaml_get(str(app_yaml), "display_name")

        click.echo(click.style(f"Restore {display_name}", fg="blue", bold=True))
        click.echo()

        # List available backups from database
        backups = db.db_list_backups(app_name)

        if not backups:
            # Fallback: check filesystem
            backup_dir = core.BACKUPS_DIR / app_name
            files = sorted(backup_dir.glob("*.tar.gz"), key=lambda f: f.stat().st_mtime, reverse=True) if backup_dir.is_dir() else []
            if not files:
                core.error(f"No backups found for {app_name}")
                raise SystemExit(1)

            core.warn("No backup records in database. Listing files:")
            click.echo()
            for i, f in enumerate(files, 1):
                size_mb = f.stat().st_size / (1024 * 1024)
                click.echo(f"  {click.style(str(i), fg='cyan')}) {f.name} ({size_mb:.1f} MB)")

            click.echo()
            choice = click.prompt("  Select backup number", type=int, default=1)
            if choice < 1 or choice > len(files):
                core.error("Invalid selection")
                raise SystemExit(1)

            selected = files[choice - 1]
            _restore_from_file(app_name, selected, install_dir, app_yaml, display_name)

        else:
            click.echo("  Available backups:")
            click.echo()
            header = f"  {'#':<4} {'TYPE':<12} {'FILE':<40} {'SIZE':<10} {'DATE'}"
            click.echo(header)
            click.echo(f"  {'---':<4} {'----':<12} {'----':<40} {'----':<10} {'----'}")

            for i, b in enumerate(backups, 1):
                size_h = _human_size(b["size_bytes"])
                fname = Path(b["path"]).name
                click.echo(f"  {i:<4} {b['type']:<12} {fname:<40} {size_h:<10} {b['created_at']}")

            click.echo()
            choice = click.prompt("  Select backup number", type=int, default=1)
            if choice < 1 or choice > len(backups):
                core.error("Invalid selection")
                raise SystemExit(1)

            selected_backup = backups[choice - 1]
            selected_path = Path(selected_backup["path"])

            if not selected_path.is_file():
                core.error(f"Backup file not found: {selected_path}")
                raise SystemExit(1)

            _restore_from_file(
                app_name, selected_path, install_dir, app_yaml,
                display_name, backup_type=selected_backup["type"],
            )


def _restore_from_file(
    app_name: str,
    archive: Path,
    install_dir: Path,
    app_yaml: Path,
    display_name: str,
    backup_type: str = "",
) -> None:
    click.echo()
    if not click.confirm(
        click.style("  This will overwrite current data. Continue?", fg="yellow"),
        default=False,
    ):
        click.echo("  Restore cancelled.")
        return

    # Verify archive integrity before proceeding
    core.step("Verifying backup integrity")
    try:
        with tarfile.open(archive, "r:gz") as tar:
            tar.getmembers()  # Force reading all headers to detect corruption
        core.success("Backup integrity verified")
    except (tarfile.TarError, EOFError, OSError) as e:
        core.error(f"Backup archive is corrupted or unreadable: {e}")
        raise SystemExit(1)

    # Stop the app
    core.step(f"Stopping {display_name}")
    core.compose_cmd(install_dir, "down", check=False, quiet_err=True)

    # Determine restore target
    if not backup_type:
        # Guess from filename
        name = archive.name
        if "_config_" in name:
            backup_type = "config"
        elif "_data_" in name:
            backup_type = "data"

    if backup_type == "config":
        core.step(f"Restoring config for {display_name}")
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(path=install_dir)
        core.success("Config restored")
    elif backup_type == "data":
        core.step(f"Restoring data for {display_name}")
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(path=core.APPDATA_DIR)
        core.success("Data restored")
    else:
        # Unknown — restore to AppData
        appdata_dirs = yaml_get_array(str(app_yaml), "appdata_dirs")
        if appdata_dirs:
            target = core.APPDATA_DIR / appdata_dirs[0]
            core.step(f"Restoring data for {display_name}")
            with tarfile.open(archive, "r:gz") as tar:
                tar.extractall(path=target)
            core.success(f"Data restored to AppData/{appdata_dirs[0]}")

    # Restart the app
    networks = yaml_get_array(str(app_yaml), "networks")
    for network in networks:
        core.ensure_network(network)

    core.step(f"Starting {display_name}")
    core.compose_cmd(install_dir, "up", "-d")
    core.success(f"{display_name} restored and running")

    db.db_log_action("restore", app_name, f"Restored from {archive.name}")


def _human_size(size_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024  # type: ignore[assignment]
    return f"{size_bytes:.1f} TB"
