"""homestack install <app> [--skip-checks]"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import click

from homestack import core, db, health, registry, secrets
from homestack.yaml_parser import yaml_get, yaml_get_array


@click.command("install")
@click.argument("app_name")
@click.option("--skip-checks", is_flag=True, help="Skip post-install health checks")
def cmd_install(app_name: str, skip_checks: bool) -> None:
    """Install an app from the catalog."""

    # Check if already installed
    if core.is_installed(app_name):
        core.error(f"'{app_name}' is already installed.")
        click.echo(f"  Run 'homestack remove {app_name}' first, or 'homestack update {app_name}'.")
        sys.exit(1)

    install_dir: Path | None = None
    install_app: str = app_name

    with core.homestack_lock():
        # Find in catalog
        source_dir = registry.registry_find(app_name)
        if not source_dir:
            core.error(f"App '{app_name}' not found in catalog.")
            click.echo("  Run 'homestack search' to see available apps.")
            sys.exit(1)

        # Normalize app_name to the canonical catalog directory name
        install_app = Path(source_dir).name
        app_yaml = Path(source_dir) / "app.yaml"
        display_name = yaml_get(str(app_yaml), "display_name")
        port_str = yaml_get(str(app_yaml), "port")
        port = int(port_str) if port_str else 0
        version = yaml_get(str(app_yaml), "version")

        click.echo(click.style(f"Installing {display_name}...", fg="blue", bold=True))
        click.echo()

        # Check port availability
        if port and not core.check_port_available(port):
            core.warn(f"Port {port} is already in use. Installation will continue but the app may fail to start.")
            if not click.confirm("  Continue anyway?", default=False):
                sys.exit(0)

        install_dir = core.INSTALLED_DIR / install_app

        try:
            # Create installed directory and copy app files
            core.step("Copying app files")
            install_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(Path(source_dir) / "compose.yaml", install_dir / "compose.yaml")
            shutil.copy2(app_yaml, install_dir / "app.yaml")
            config_src = Path(source_dir) / "config.env"
            if config_src.is_file():
                shutil.copy2(config_src, install_dir / "config.env")
            # Copy test.yaml for post-install health checks
            test_src = Path(source_dir) / "test.yaml"
            if test_src.is_file():
                shutil.copy2(test_src, install_dir / "test.yaml")
            core.success(f"App files copied to installed/{install_app}")

            # Create required Docker networks
            networks = yaml_get_array(str(app_yaml), "networks")
            for network in networks:
                core.ensure_network(network)

            # Create required AppData directories
            appdata_dirs = yaml_get_array(str(app_yaml), "appdata_dirs")
            for d in appdata_dirs:
                if not core.validate_path_component(d):
                    sys.exit(1)
                core.ensure_dir(core.APPDATA_DIR / d)
            if appdata_dirs:
                core.success("AppData directories created")

            # Create required Media directories
            media_dirs = yaml_get_array(str(app_yaml), "media_dirs")
            for d in media_dirs:
                if not core.validate_path_component(d):
                    sys.exit(1)
                core.ensure_dir(core.MEDIA_DIR / d)
            if media_dirs:
                core.success("Media directories created")

            # Generate secrets
            secrets.generate_secrets_file(str(app_yaml), str(install_dir / "secrets.env"))

            # Track config defaults in database
            db.db_track_config_defaults(install_app, install_dir / "config.env")

            # Start the app
            core.step(f"Starting {display_name}")
            core.compose_cmd(install_dir, "up", "-d")

            # Post-install health checks
            if not skip_checks:
                checks_passed = health.run_health_checks(install_app, install_dir)
                if not checks_passed:
                    core.error(f"Health checks failed for {display_name}")
                    raise RuntimeError("Health checks failed")
            else:
                core.warn("Health checks skipped (--skip-checks)")

            # Record in database
            db.db_set_installed(install_app, version)
            db.db_log_action("install", install_app, f"Installed version {version}")

            click.echo()
            core.success(f"{display_name} installed and running on port {port}")
            click.echo()
            click.echo("  Manage with:")
            click.echo(f"    homestack stop {install_app}")
            click.echo(f"    homestack start {install_app}")
            click.echo(f"    homestack remove {install_app}")
            if (install_dir / "config.env").is_file():
                click.echo(f"  Edit config:  {install_dir}/config.env")

        except Exception:
            # Rollback on any failure
            core.warn("Installation failed, rolling back...")
            try:
                core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
            except Exception:
                pass
            if install_dir and install_dir.is_dir():
                shutil.rmtree(install_dir, ignore_errors=True)
            db.db_remove_app(install_app)
            db.db_log_action("install", install_app, "Installation failed — rolled back", 1)
            sys.exit(1)
