"""homestack exec <app> <command...>"""

from __future__ import annotations

import sys

import click

from homestack import core
from homestack.yaml_parser import yaml_get


@click.command("exec", context_settings={"ignore_unknown_options": True})
@click.argument("app_name")
@click.argument("command", nargs=-1, required=True)
@click.option("-s", "--service", default=None, help="Target service name (defaults to first service)")
def cmd_exec(app_name: str, command: tuple[str, ...], service: str | None) -> None:
    """Run a command inside an app's container."""

    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        sys.exit(1)

    install_dir = core.INSTALLED_DIR / app_name

    args = ["exec"]
    if service:
        args.append(service)
    else:
        # Use the first service from compose.yaml
        from homestack.yaml_parser import load_yaml
        data = load_yaml(str(install_dir / "compose.yaml"))
        services = list(data.get("services", {}).keys())
        if not services:
            core.error("No services found in compose.yaml")
            sys.exit(1)
        args.append(services[0])

    args.extend(command)

    try:
        result = core.compose_cmd(install_dir, *args, check=False)
        sys.exit(result.returncode)
    except KeyboardInterrupt:
        pass
