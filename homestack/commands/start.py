"""homestack start [app]"""

from __future__ import annotations

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get, yaml_get_array


@click.command("start")
@click.argument("app_name", required=False, default=None)
def cmd_start(app_name: str | None) -> None:
    """Start one or all installed apps."""

    with core.homestack_lock():
        if app_name:
            _start_one(app_name)
        else:
            apps = core.get_installed_apps()
            if not apps:
                core.warn("No apps installed. Run 'homestack search' to find apps.")
                return
            click.echo(click.style("Starting all apps...", fg="blue", bold=True))
            for app in apps:
                _start_one(app, quiet=True)
            click.echo()
            core.success("All apps started")
            db.db_log_action("start", "", "Started all apps")


def _start_one(app_name: str, *, quiet: bool = False) -> None:
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    install_dir = core.INSTALLED_DIR / app_name
    app_yaml = install_dir / "app.yaml"
    display_name = yaml_get(str(app_yaml), "display_name")

    # Ensure networks exist
    networks = yaml_get_array(str(app_yaml), "networks")
    for network in networks:
        core.ensure_network(network)

    core.step(f"Starting {display_name}")
    core.compose_cmd(install_dir, "up", "-d")
    core.success(f"{display_name} started")

    if not quiet:
        db.db_log_action("start", app_name, "Started")
