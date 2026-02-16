"""homestack doctor — System health check."""

from __future__ import annotations

import shutil
import subprocess

import click

from homestack import core, db


@click.command("doctor")
def cmd_doctor() -> None:
    """Check system health and HomeStack configuration."""

    click.echo(click.style("HomeStack Doctor", fg="blue", bold=True))
    click.echo()

    all_ok = True

    # 1. Check Docker
    _ok = _check("Docker installed", shutil.which("docker") is not None)
    all_ok = all_ok and _ok

    if _ok:
        r = subprocess.run(
            ["docker", "info"], capture_output=True, text=True,
        )
        _ok = _check("Docker daemon running", r.returncode == 0)
        all_ok = all_ok and _ok

    # 2. Check Docker Compose v2
    r = subprocess.run(
        ["docker", "compose", "version"], capture_output=True, text=True,
    )
    compose_ok = r.returncode == 0
    _check("Docker Compose v2", compose_ok)
    if compose_ok and r.stdout:
        click.echo(f"       {r.stdout.strip()}")
    all_ok = all_ok and compose_ok

    # 3. Check git
    _ok = _check("Git installed", shutil.which("git") is not None)
    all_ok = all_ok and _ok

    # 4. Check HomeStack directory
    _ok = _check("HomeStack directory", core.HOMESTACK_DIR.is_dir())
    all_ok = all_ok and _ok

    # 5. Check config file
    _ok = _check("Config file exists", core.CONFIG_FILE.is_file())
    all_ok = all_ok and _ok

    # 6. Check database
    _ok = _check("Database accessible", core.DB_FILE.is_file())
    all_ok = all_ok and _ok

    if _ok:
        try:
            db.db_init()
            _check("Database schema OK", True)
        except Exception as e:
            _check(f"Database schema: {e}", False)
            all_ok = False

    # 7. Check catalog
    catalog_ok = core.APPS_DIR.is_dir()
    _check("App catalog cached", catalog_ok)
    if catalog_ok:
        app_count = sum(1 for d in core.APPS_DIR.iterdir()
                        if d.is_dir() and (d / "app.yaml").is_file())
        click.echo(f"       {app_count} apps available")
    all_ok = all_ok and catalog_ok

    # 8. Check WAL file size
    wal_file = core.DB_FILE.with_name(core.DB_FILE.name + "-wal")
    if wal_file.is_file():
        wal_size = wal_file.stat().st_size
        if wal_size > 10 * 1024 * 1024:
            _check(f"WAL file ({wal_size // (1024*1024)} MB — consider running PRAGMA wal_checkpoint)", False)
            all_ok = False
        else:
            _check("WAL file size OK", True)

    # 9. Check disk space
    import os
    stat = os.statvfs(str(core.HOMESTACK_DIR))
    free_gb = (stat.f_bavail * stat.f_frsize) / (1024 ** 3)
    _ok = _check(f"Disk space ({free_gb:.1f} GB free)", free_gb > 1.0)
    all_ok = all_ok and _ok

    # 10. List installed apps
    apps = core.get_installed_apps()
    click.echo()
    if apps:
        click.echo(f"  Installed apps: {', '.join(apps)}")
    else:
        click.echo("  No apps installed")

    # Summary
    click.echo()
    if all_ok:
        core.success("All checks passed")
    else:
        core.warn("Some checks failed — review the output above")


def _check(label: str, ok: bool) -> bool:
    """Print a check result line."""
    if ok:
        click.echo(click.style(f"  ✓ {label}", fg="green"))
    else:
        click.echo(click.style(f"  ✗ {label}", fg="red"))
    return ok
