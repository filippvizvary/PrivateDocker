"""homestack search [query]"""

from __future__ import annotations

import click

from homestack import core
from homestack.registry import registry_ensure, registry_list, registry_search


@click.command("search")
@click.argument("query", required=False, default=None)
def cmd_search(query: str | None) -> None:
    """Search the app catalog (no lock needed)."""

    registry_ensure()

    if query:
        results = registry_search(query)
    else:
        results = registry_list()

    if not results:
        msg = f" matching '{query}'" if query else ""
        click.echo(f"No apps found{msg}.")
        click.echo("  Try 'homestack catalog update' to refresh the catalog.")
        return

    click.echo(click.style("Available Apps", fg="blue", bold=True))
    click.echo()
    click.echo(f"  {'NAME':<18} {'CATEGORY':<15} {'PORT':<8} {'DESCRIPTION'}")
    click.echo(f"  {'----':<18} {'--------':<15} {'----':<8} {'-----------'}")

    for app in results:
        marker = click.style(" ✓", fg="green") if core.is_installed(app["name"]) else ""
        click.echo(
            f"  {app['name']:<18} {app.get('category', '-'):<15} "
            f"{str(app.get('port', '-')):<8} {app.get('description', '')}{marker}"
        )

    click.echo()
    click.echo("  Install with: homestack install <name>")
    click.echo(f"  {click.style('✓', fg='green')} = already installed")
    click.echo()
