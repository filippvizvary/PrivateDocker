"""homestack stop [app]"""

from __future__ import annotations

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get


@click.command("stop")
@click.argument("app_name", required=False, default=None)
def cmd_stop(app_name: str | None) -> None:
    """Stop one or all installed apps."""

    with core.homestack_lock():
        if app_name:
            _stop_one(app_name)
        else:
            apps = core.get_installed_apps()
            if not apps:
                core.warn("No apps installed.")
                return
            # Stop in reverse priority order (high-priority apps stop last)
            reversed_apps = list(reversed(apps))
            click.echo(click.style("Stopping all apps...", fg="blue", bold=True))
            for app in reversed_apps:
                _stop_one(app, quiet=True)
            click.echo()
            core.success("All apps stopped")
            db.db_log_action("stop", "", "Stopped all apps")


def _stop_one(app_name: str, *, quiet: bool = False) -> None:
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)

    install_dir = core.INSTALLED_DIR / app_name
    display_name = yaml_get(str(install_dir / "app.yaml"), "display_name")

    core.step(f"Stopping {display_name}")
    core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
    core.success(f"{display_name} stopped")

    if not quiet:
        db.db_log_action("stop", app_name, "Stopped")
