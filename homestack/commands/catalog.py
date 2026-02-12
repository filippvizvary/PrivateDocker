"""homestack catalog [update|list]"""

from __future__ import annotations

import click

from homestack import core
from homestack.registry import registry_ensure, registry_list, registry_sync


@click.group("catalog", invoke_without_command=True)
@click.pass_context
def cmd_catalog(ctx: click.Context) -> None:
    """Manage the app catalog."""
    if ctx.invoked_subcommand is None:
        # Default action: update
        registry_sync()


@cmd_catalog.command("update")
def catalog_update() -> None:
    """Sync the catalog from GitHub."""
    registry_sync()


@cmd_catalog.command("list")
def catalog_list() -> None:
    """List all apps in the catalog."""
    registry_ensure()

    apps = registry_list()
    if not apps:
        click.echo("Catalog is empty. Try 'homestack catalog update' first.")
        return

    click.echo(click.style("App Catalog", fg="blue", bold=True))
    click.echo()
    click.echo(f"  {'NAME':<18} {'CATEGORY':<15} {'PORT':<8} {'DESCRIPTION'}")
    click.echo(f"  {'----':<18} {'--------':<15} {'----':<8} {'-----------'}")

    for app in apps:
        marker = click.style(" ✓", fg="green") if core.is_installed(app["name"]) else ""
        name_styled = click.style(app["name"], fg="cyan")
        # Pad manually since styled text has escape codes
        pad = " " * max(0, 18 - len(app["name"]))
        click.echo(
            f"  {name_styled}{pad} {app.get('category', '-'):<15} "
            f"{str(app.get('port', '-')):<8} {app.get('description', '')}{marker}"
        )

    click.echo()
    click.echo("  Install with: homestack install <name>")
    click.echo(f"  {click.style('✓', fg='green')} = already installed")
    click.echo()
