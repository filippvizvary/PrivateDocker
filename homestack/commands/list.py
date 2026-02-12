"""homestack list"""

from __future__ import annotations

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get


@click.command("list")
def cmd_list() -> None:
    """List all installed apps (no lock needed)."""

    apps = core.get_installed_apps()
    if not apps:
        click.echo("No apps installed.")
        click.echo("  Run 'homestack search' to browse the catalog.")
        return

    click.echo(click.style("Installed Apps", fg="blue", bold=True))
    click.echo()
    click.echo(f"  {'NAME':<18} {'CATEGORY':<15} {'PORT':<8} {'VERSION':<12} {'INSTALLED'}")
    click.echo(f"  {'----':<18} {'--------':<15} {'----':<8} {'-------':<12} {'---------'}")

    for app in apps:
        install_dir = core.INSTALLED_DIR / app
        app_yaml = install_dir / "app.yaml"
        display_name = yaml_get(str(app_yaml), "display_name")
        category = yaml_get(str(app_yaml), "category") or "-"
        port = yaml_get(str(app_yaml), "port") or "-"
        version = yaml_get(str(app_yaml), "version") or "-"
        installed_at = db.db_get_install_date(app) or "-"
        click.echo(
            f"  {display_name:<18} {category:<15} {str(port):<8} {str(version):<12} {installed_at}"
        )

    click.echo()
