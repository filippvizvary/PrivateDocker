"""homestack restart [app]"""

from __future__ import annotations

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get, yaml_get_array


@click.command("restart")
@click.argument("app_name", required=False, default=None)
def cmd_restart(app_name: str | None) -> None:
    """Restart one or all installed apps."""

    with core.homestack_lock():
        if app_name:
            _restart_one(app_name)
        else:
            apps = core.get_installed_apps()
            if not apps:
                core.warn("No apps installed.")
                return

            click.echo(click.style("Restarting all apps...", fg="blue", bold=True))

            # Stop in reverse priority
            for app in reversed(apps):
                install_dir = core.INSTALLED_DIR / app
                display_name = yaml_get(str(install_dir / "app.yaml"), "display_name")
                core.step(f"Stopping {display_name}")
                core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
                core.success(f"{display_name} stopped")

            # Start in priority order
            for app in apps:
                install_dir = core.INSTALLED_DIR / app
                app_yaml = install_dir / "app.yaml"
                display_name = yaml_get(str(app_yaml), "display_name")
                for network in yaml_get_array(str(app_yaml), "networks"):
                    core.ensure_network(network)
                core.step(f"Starting {display_name}")
                core.compose_cmd(install_dir, "up", "-d")
                core.success(f"{display_name} started")

            click.echo()
            core.success("All apps restarted")
            db.db_log_action("restart", "", "Restarted all apps")


def _restart_one(app_name: str) -> None:
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    install_dir = core.INSTALLED_DIR / app_name
    app_yaml = install_dir / "app.yaml"
    display_name = yaml_get(str(app_yaml), "display_name")

    core.step(f"Restarting {display_name}")
    core.compose_cmd(install_dir, "down", check=False, quiet_err=True)

    for network in yaml_get_array(str(app_yaml), "networks"):
        core.ensure_network(network)

    core.compose_cmd(install_dir, "up", "-d")
    core.success(f"{display_name} restarted")
    db.db_log_action("restart", app_name, "Restarted")
