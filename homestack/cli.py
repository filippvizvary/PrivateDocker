"""HomeStack — Click CLI entrypoint.

Registers all subcommands and provides ``homestack`` as a console script.
"""

from __future__ import annotations

import sys

import click

from homestack import __version__, db


@click.group(invoke_without_command=True)
@click.version_option(__version__, prog_name="HomeStack")
@click.pass_context
def cli(ctx: click.Context) -> None:
    """HomeStack — Self-hosted Docker management CLI."""
    # Initialise database on every invocation
    db.db_init()

    if ctx.invoked_subcommand is None:
        click.echo(ctx.get_help())


# ── Register commands ──────────────────────────────────────────────────────

from homestack.commands.install import cmd_install     # noqa: E402
from homestack.commands.update import cmd_update       # noqa: E402
from homestack.commands.remove import cmd_remove       # noqa: E402
from homestack.commands.backup import cmd_backup       # noqa: E402
from homestack.commands.restore import cmd_restore     # noqa: E402
from homestack.commands.start import cmd_start         # noqa: E402
from homestack.commands.stop import cmd_stop           # noqa: E402
from homestack.commands.restart import cmd_restart     # noqa: E402
from homestack.commands.status import cmd_status       # noqa: E402
from homestack.commands.list import cmd_list           # noqa: E402
from homestack.commands.search import cmd_search       # noqa: E402
from homestack.commands.catalog import cmd_catalog     # noqa: E402

cli.add_command(cmd_install)
cli.add_command(cmd_update)
cli.add_command(cmd_remove)
cli.add_command(cmd_backup)
cli.add_command(cmd_restore)
cli.add_command(cmd_start)
cli.add_command(cmd_stop)
cli.add_command(cmd_restart)
cli.add_command(cmd_status)
cli.add_command(cmd_list)
cli.add_command(cmd_search)
cli.add_command(cmd_catalog)


# ── Log command (inline — too small for its own file) ──────────────────────

@cli.command("log")
@click.argument("limit", required=False, default=20, type=int)
def cmd_log(limit: int) -> None:
    """Show the audit log."""
    entries = db.db_get_audit_log(limit)
    click.echo(click.style(f"Audit Log (last {limit} entries)", fg="blue", bold=True))
    click.echo()
    click.echo(f"  {'TIMESTAMP':<20} {'ACTION':<10} {'APP':<15} {'DETAIL'}")
    click.echo(f"  {'---------':<20} {'------':<10} {'---':<15} {'------'}")
    for e in entries:
        colour = "red" if e.get("exit_code", 0) != 0 else None
        ts = e.get("timestamp", "")
        action = e.get("action", "")
        app = e.get("app") or "—"
        detail = e.get("detail") or "—"
        line = f"  {ts:<20} {action:<10} {app:<15} {detail}"
        if colour:
            line = click.style(line, fg=colour)
        click.echo(line)
    click.echo()
