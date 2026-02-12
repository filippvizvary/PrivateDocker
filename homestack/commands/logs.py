"""homestack logs <app> [--follow] [--tail N]"""

from __future__ import annotations

import subprocess
import sys

import click

from homestack import core
from homestack.yaml_parser import yaml_get


@click.command("logs")
@click.argument("app_name")
@click.option("-f", "--follow", is_flag=True, help="Follow log output")
@click.option("-n", "--tail", default=100, type=int, help="Number of lines to show")
def cmd_logs(app_name: str, follow: bool, tail: int) -> None:
    """View logs for an installed app."""

    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        sys.exit(1)

    install_dir = core.INSTALLED_DIR / app_name

    args = ["logs", "--tail", str(tail)]
    if follow:
        args.append("--follow")

    try:
        core.compose_cmd(install_dir, *args, check=False)
    except KeyboardInterrupt:
        pass
