"""homestack remove <app>"""

from __future__ import annotations

import shutil
import subprocess
import sys

import click

from homestack import core, db
from homestack.yaml_parser import yaml_get, yaml_get_array


@click.command("remove")
@click.argument("app_name")
@click.option("-y", "--yes", is_flag=True, help="Skip confirmation prompts.")
def cmd_remove(app_name: str, yes: bool) -> None:
    """Stop and remove an installed app."""

    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        sys.exit(1)

    with core.homestack_lock():
        install_dir = core.INSTALLED_DIR / app_name
        app_yaml = install_dir / "app.yaml"
        display_name = yaml_get(str(app_yaml), "display_name")

        click.echo(click.style(f"Removing {display_name}...", fg="blue", bold=True))

        # Warn if other installed apps depend on this one
        dependents = []
        for other_app in core.get_installed_apps():
            if other_app == app_name:
                continue
            other_yaml = core.INSTALLED_DIR / other_app / "app.yaml"
            if other_yaml.is_file():
                other_deps = yaml_get_array(str(other_yaml), "depends_on")
                if app_name in other_deps:
                    dependents.append(other_app)
        if dependents:
            core.warn(f"These apps depend on {display_name}: {', '.join(dependents)}")
            if not yes and not click.confirm("  Continue with removal?", default=False):
                sys.exit(0)

        # Stop containers
        core.step("Stopping containers")
        try:
            core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
        except Exception:
            core.warn("Some containers may not have stopped cleanly")
        core.success("Containers stopped")

        # Clean up Docker networks specific to this app
        networks = yaml_get_array(str(app_yaml), "networks")
        for network in networks:
            try:
                result = subprocess.run(
                    ["docker", "network", "inspect", network,
                     "--format", "{{len .Containers}}"],
                    capture_output=True, text=True,
                )
                connected = result.stdout.strip()
                if connected == "0":
                    subprocess.run(
                        ["docker", "network", "rm", network],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    core.success(f"Removed Docker network '{network}'")
            except Exception:
                pass

        # Ask about AppData
        appdata_dirs = yaml_get_array(str(app_yaml), "appdata_dirs")
        if appdata_dirs:
            delete_data = yes or click.confirm(
                click.style("\n  Delete app data in AppData/? This cannot be undone.", fg="red"),
                default=False,
            )
            if delete_data:
                for d in appdata_dirs:
                    if not core.validate_path_component(d):
                        continue
                    target = core.APPDATA_DIR / d
                    if target.is_dir():
                        try:
                            shutil.rmtree(target)
                        except PermissionError:
                            # Container-created files may be owned by another user;
                            # fall back to removing via a privileged container.
                            subprocess.run(
                                ["docker", "run", "--rm",
                                 "-v", f"{target}:/data",
                                 "alpine", "rm", "-rf", "/data"],
                                capture_output=True,
                            )
                            # Remove the now-empty host directory
                            shutil.rmtree(target, ignore_errors=True)
                core.success("AppData deleted")
            else:
                core.success(f"AppData preserved in {core.APPDATA_DIR}/")

        # Remove installed files
        shutil.rmtree(install_dir, ignore_errors=True)

        # Remove from database
        db.db_remove_app(app_name)
        db.db_log_action("remove", app_name, f"Removed {display_name}")

    core.success(f"{display_name} removed")
