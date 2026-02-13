"""homestack config <subcommand> <app>"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get


@click.group("config")
def cmd_config() -> None:
    """View or edit app configuration."""


@cmd_config.command("show")
@click.argument("app_name")
def cmd_config_show(app_name: str) -> None:
    """Show current configuration for an app."""
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    install_dir = core.INSTALLED_DIR / app_name
    app_yaml = install_dir / "app.yaml"
    config_file = install_dir / "config.env"
    display_name = yaml_get(str(app_yaml), "display_name")

    click.echo(click.style(f"Config — {display_name}", fg="blue", bold=True))
    click.echo()

    if not config_file.is_file():
        core.warn("No config.env found")
        return

    modified = dict(db.db_get_modified_configs(app_name))

    click.echo(f"  {'KEY':<30} {'VALUE':<35} {'STATUS'}")
    click.echo(f"  {'---':<30} {'-----':<35} {'------'}")

    for line in config_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("\"'")

        if key in modified:
            status = click.style("modified", fg="yellow")
        else:
            status = click.style("default", fg="green")

        # Truncate long values
        display_val = value if len(value) <= 35 else value[:32] + "..."
        click.echo(f"  {key:<30} {display_val:<35} {status}")

    click.echo()
    click.echo(f"  Config file: {config_file}")
    click.echo()


@cmd_config.command("edit")
@click.argument("app_name")
@click.argument("key")
@click.argument("value")
def cmd_config_edit(app_name: str, key: str, value: str) -> None:
    """Set a config value for an app.

    Example: homestack config edit jellyfin JELLYFIN_PORT 8097
    """
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    with core.homestack_lock():
        install_dir = core.INSTALLED_DIR / app_name
        config_file = install_dir / "config.env"

        if not config_file.is_file():
            core.error(f"No config.env found for {app_name}")
            raise SystemExit(1)

        # Read current config
        lines = config_file.read_text().splitlines()
        found = False
        old_value = None
        for i, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if "=" not in stripped:
                continue
            k, _, v = stripped.partition("=")
            if k.strip() == key:
                old_value = v.strip().strip("\"'")
                lines[i] = f"{key}={value}"
                found = True
                break

        if not found:
            core.error(f"Key '{key}' not found in config.env")
            click.echo(f"  Available keys:")
            for line in config_file.read_text().splitlines():
                stripped = line.strip()
                if stripped and not stripped.startswith("#") and "=" in stripped:
                    k, _, _ = stripped.partition("=")
                    click.echo(f"    {k.strip()}")
            raise SystemExit(1)

        # Write updated config
        config_file.write_text("\n".join(lines) + "\n")

        # Mark as user-modified in DB
        db.db_mark_config_modified(app_name, key, value)

        core.success(f"{key}: {old_value} → {value}")

        # Ask to restart
        display_name = yaml_get(str(install_dir / "app.yaml"), "display_name")
        if click.confirm(f"  Restart {display_name} to apply changes?", default=True):
            core.step(f"Restarting {display_name}")
            core.compose_cmd(install_dir, "up", "-d", "--remove-orphans")
            core.success(f"{display_name} restarted with updated config")

        db.db_log_action("config", app_name, f"Set {key}={value}")


@cmd_config.command("reset")
@click.argument("app_name")
@click.argument("key")
def cmd_config_reset(app_name: str, key: str) -> None:
    """Reset a config key to its catalog default."""
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    with core.homestack_lock():
        install_dir = core.INSTALLED_DIR / app_name
        config_file = install_dir / "config.env"

        if not config_file.is_file():
            core.error(f"No config.env found for {app_name}")
            raise SystemExit(1)

        # Get default from DB
        from homestack.db import _connect
        with _connect() as conn:
            row = conn.execute(
                "SELECT value FROM config_overrides WHERE app = ? AND key = ?",
                (app_name, key),
            ).fetchone()

        if row is None:
            core.error(f"No default value tracked for '{key}'")
            raise SystemExit(1)

        default_value = row[0]

        # Update config file
        lines = config_file.read_text().splitlines()
        for i, line in enumerate(lines):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if "=" not in stripped:
                continue
            k, _, _ = stripped.partition("=")
            if k.strip() == key:
                lines[i] = f"{key}={default_value}"
                break

        config_file.write_text("\n".join(lines) + "\n")

        # Reset the modified flag in DB
        with _connect() as conn:
            conn.execute(
                "UPDATE config_overrides SET value = ?, is_user_modified = 0 "
                "WHERE app = ? AND key = ?",
                (default_value, app_name, key),
            )

        core.success(f"{key} reset to default: {default_value}")
        db.db_log_action("config", app_name, f"Reset {key} to default")
