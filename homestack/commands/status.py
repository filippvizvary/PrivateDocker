"""homestack status [app]"""

from __future__ import annotations

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get


@click.command("status")
@click.argument("app_name", required=False, default=None)
def cmd_status(app_name: str | None) -> None:
    """Show status of installed apps (no lock needed)."""

    if app_name:
        if not core.is_installed(app_name):
            core.error(f"'{app_name}' is not installed.")
            raise SystemExit(1)
        apps = [app_name]
    else:
        apps = core.get_installed_apps()
        if not apps:
            core.warn("No apps installed.")
            return

    click.echo(click.style("HomeStack — Service Status", fg="blue", bold=True))
    click.echo()

    header = f"  {'APP':<18} {'PORT':<12} {'STATUS':<30} {'CONTAINERS'}"
    click.echo(header)
    click.echo(f"  {'---':<18} {'----':<12} {'------':<30} {'----------'}")

    for app in apps:
        install_dir = core.INSTALLED_DIR / app
        app_yaml = install_dir / "app.yaml"
        display_name = yaml_get(str(app_yaml), "display_name")
        port = yaml_get(str(app_yaml), "port") or "-"

        # Get container statuses
        result = core.compose_cmd(
            install_dir, "ps", "--format", "{{.Name}}\t{{.Status}}",
            capture=True, check=False, quiet_err=True,
        )

        containers = result.stdout.strip() if result.stdout else ""

        if not containers:
            status_text = click.style(f"{'stopped':<30}", fg="red")
            click.echo(f"  {display_name:<18} {str(port):<12} {status_text} -")
            db.db_update_health(app, app, "stopped")
        else:
            first = True
            for line in containers.splitlines():
                if "\t" not in line:
                    continue
                cname, cstatus = line.split("\t", 1)

                # Determine colour
                if "unhealthy" in cstatus.lower():
                    colour = "red"
                elif "up" in cstatus.lower() or "running" in cstatus.lower():
                    colour = "green"
                elif "exited" in cstatus.lower() or "dead" in cstatus.lower():
                    colour = "red"
                elif "restarting" in cstatus.lower():
                    colour = "yellow"
                else:
                    colour = "white"

                styled = click.style(f"{cstatus:<30}", fg=colour)
                if first:
                    click.echo(f"  {display_name:<18} {str(port):<12} {styled} {cname}")
                    first = False
                else:
                    click.echo(f"  {'':<18} {'':<12} {styled} {cname}")

                db.db_update_health(app, cname, cstatus)

    click.echo()
