"""homestack update [app]"""

from __future__ import annotations

import os
import shutil
import sys
import tarfile
from datetime import datetime
from pathlib import Path

import click

from homestack import core, db, secrets as secrets_mod
from homestack.yaml_parser import yaml_get, yaml_get_array
from homestack import registry, health as health_mod


@click.command("update")
@click.argument("app_name", required=False, default=None)
@click.option("--skip-checks", is_flag=True, help="Skip post-update health checks")
@click.option("--dry-run", is_flag=True, help="Show what would be updated without making changes")
def cmd_update(app_name: str | None, skip_checks: bool, dry_run: bool) -> None:
    """Update all or a specific app."""

    with core.homestack_lock():
        if app_name:
            _update_app(app_name, skip_checks=skip_checks, dry_run=dry_run)
        else:
            apps = core.get_installed_apps()
            if not apps:
                core.warn("No apps installed.")
                return

            if dry_run:
                click.echo(click.style("Update check (dry run)", fg="blue", bold=True))
                click.echo()
                registry.registry_sync()
                any_updates = False
                for app in apps:
                    install_dir = core.INSTALLED_DIR / app
                    app_yaml = install_dir / "app.yaml"
                    if not app_yaml.is_file():
                        continue
                    display_name = yaml_get(str(app_yaml), "display_name")
                    catalog_dir = registry.registry_find(app)
                    if catalog_dir:
                        installed_ver = yaml_get(str(app_yaml), "version")
                        catalog_ver = yaml_get(str(Path(catalog_dir) / "app.yaml"), "version")
                        if installed_ver != catalog_ver:
                            click.echo(f"  {display_name}: {installed_ver} \u2192 {catalog_ver} "
                                       + click.style("(update available)", fg="yellow"))
                            any_updates = True
                        else:
                            click.echo(f"  {display_name}: {installed_ver} "
                                       + click.style("(up to date)", fg="green"))
                if not any_updates:
                    click.echo()
                    core.success("All apps are up to date")
                click.echo()
                return

            click.echo(click.style("Updating all apps...", fg="blue", bold=True))
            for app in apps:
                _update_app(app, skip_checks=skip_checks)
            click.echo()
            core.success("All apps updated")


def _update_app(app_name: str, skip_checks: bool = False, dry_run: bool = False) -> None:
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        return

    install_dir = core.INSTALLED_DIR / app_name
    app_yaml = install_dir / "app.yaml"
    display_name = yaml_get(str(app_yaml), "display_name")

    # Check if a newer version exists in the catalog
    catalog_dir = registry.registry_find(app_name)

    if catalog_dir:
        catalog_path = Path(catalog_dir)
        installed_ver = yaml_get(str(app_yaml), "version")
        catalog_ver = yaml_get(str(catalog_path / "app.yaml"), "version")

        if installed_ver != catalog_ver:
            if dry_run:
                click.echo(f"  {display_name}: {installed_ver} \u2192 {catalog_ver} "
                           + click.style("(update available)", fg="yellow"))
                return

            core.step(f"Updating {display_name}: {installed_ver} → {catalog_ver}")

            # Auto-backup config before update
            core.step("Backing up current config")
            backup_dir = core.BACKUPS_DIR / app_name
            core.ensure_dir(backup_dir)
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            config_backup = backup_dir / f"{app_name}_config_preupdate_{ts}.tar.gz"
            with tarfile.open(config_backup, "w:gz") as tar:
                for f in install_dir.iterdir():
                    tar.add(f, arcname=f.name)
            backup_size = config_backup.stat().st_size
            db.db_record_backup(app_name, str(config_backup), backup_size, "config")
            core.success("Config backed up before update")

            # Update app.yaml, compose.yaml, and test.yaml from catalog
            shutil.copy2(catalog_path / "app.yaml", install_dir / "app.yaml")
            shutil.copy2(catalog_path / "compose.yaml", install_dir / "compose.yaml")
            test_yaml = catalog_path / "test.yaml"
            if test_yaml.is_file():
                shutil.copy2(test_yaml, install_dir / "test.yaml")

            # Smart config merge: preserve user-modified values
            new_config = catalog_path / "config.env"
            if new_config.is_file():
                _merge_config(app_name, install_dir, new_config)

            # Handle new secrets
            interactive = os.isatty(sys.stdin.fileno())
            if (install_dir / "secrets.env").is_file():
                secrets_mod.append_new_secrets(
                    str(install_dir / "app.yaml"),
                    str(install_dir / "secrets.env"),
                    interactive=interactive,
                )

            # Update DB
            db.db_set_updated(app_name, catalog_ver)
            # Re-track config defaults from the new catalog version
            db.db_track_config_defaults(app_name, str(new_config))

    core.step(f"Pulling latest images for {display_name}")
    core.compose_cmd(install_dir, "pull", check=False, quiet_err=True)

    core.step(f"Recreating {display_name}")
    try:
        core.compose_cmd(install_dir, "up", "-d", "--remove-orphans")

        # Post-update health checks
        if not skip_checks:
            checks_passed = health_mod.run_health_checks(app_name, install_dir)
            if not checks_passed:
                core.warn(f"Health checks failed for {display_name} after update")
        else:
            core.warn("Health checks skipped (--skip-checks)")

        core.success(f"{display_name} updated")
        db.db_log_action("update", app_name, "Updated successfully")
    except Exception:
        core.error(f"Failed to recreate {display_name}")
        db.db_log_action("update", app_name, "Update failed during recreate", 1)


def _merge_config(app_name: str, install_dir: Path, new_config: Path) -> None:
    """Smart merge: keep user-modified values, update defaults, add new keys."""
    current_config = install_dir / "config.env"

    if not current_config.is_file():
        shutil.copy2(new_config, current_config)
        return

    # Read current values
    current_values: dict[str, str] = {}
    for line in current_config.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        current_values[key.strip()] = value.strip().strip("\"'")

    # Start with the new config as base
    merged_path = install_dir / "config.env.new"
    shutil.copy2(new_config, merged_path)

    # For each key in current config, check if user modified it
    for key, current_value in current_values.items():
        if db.db_is_config_modified(app_name, key, current_value):
            # User modified this — preserve their value in merged file
            merged_text = merged_path.read_text()
            lines = merged_text.splitlines()
            found = False
            for i, line in enumerate(lines):
                if line.startswith(f"{key}="):
                    lines[i] = f"{key}={current_value}"
                    found = True
                    break
            if not found:
                lines.append(f"{key}={current_value}")
            merged_path.write_text("\n".join(lines) + "\n")
            core.warn(f"Preserved user-modified config: {key}")

    merged_path.rename(current_config)
