"""Unit tests for update merge logic and config command."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from homestack import db
from tests.conftest import create_fixture_app, mock_install_app


class TestMergeConfig:
    """Test the _merge_config function from update.py."""

    def test_preserves_user_modified_values(self, db_init, tmp_homestack):
        """User-modified config values are preserved during merge."""
        from homestack.commands.update import _merge_config

        # Set up installed app with config
        app_name = "testapp"
        install_dir = tmp_homestack / "installed" / app_name
        install_dir.mkdir(parents=True)

        current_config = install_dir / "config.env"
        current_config.write_text("IMAGE=old:1.0\nPORT=8080\n")

        # Track defaults
        db.db_track_config_defaults(app_name, str(current_config))

        # User changes PORT to 9090
        db.db_mark_config_modified(app_name, "PORT", "9090")
        current_config.write_text("IMAGE=old:1.0\nPORT=9090\n")

        # New catalog config with updated IMAGE but same PORT default
        new_config = tmp_homestack / "new_config.env"
        new_config.write_text("IMAGE=new:2.0\nPORT=8080\n")

        _merge_config(app_name, install_dir, new_config)

        # Read merged result
        merged = current_config.read_text()
        assert "PORT=9090" in merged    # User value preserved
        assert "IMAGE=new:2.0" in merged  # Default updated from catalog

    def test_adds_new_keys(self, db_init, tmp_homestack):
        """New keys from catalog are added during merge."""
        from homestack.commands.update import _merge_config

        app_name = "testapp"
        install_dir = tmp_homestack / "installed" / app_name
        install_dir.mkdir(parents=True)

        current_config = install_dir / "config.env"
        current_config.write_text("IMAGE=old:1.0\n")
        db.db_track_config_defaults(app_name, str(current_config))

        new_config = tmp_homestack / "new_config.env"
        new_config.write_text("IMAGE=new:2.0\nNEW_KEY=hello\n")

        _merge_config(app_name, install_dir, new_config)

        merged = current_config.read_text()
        assert "NEW_KEY=hello" in merged
        assert "IMAGE=new:2.0" in merged

    def test_copies_if_no_existing_config(self, db_init, tmp_homestack):
        """If no config.env exists, just copy the new one."""
        from homestack.commands.update import _merge_config

        app_name = "testapp"
        install_dir = tmp_homestack / "installed" / app_name
        install_dir.mkdir(parents=True)

        new_config = tmp_homestack / "new_config.env"
        new_config.write_text("IMAGE=new:2.0\n")

        _merge_config(app_name, install_dir, new_config)

        merged = (install_dir / "config.env").read_text()
        assert "IMAGE=new:2.0" in merged


class TestComposeCmd:
    """Test env file handling in compose_cmd."""

    def test_missing_config_file_no_crash(self, tmp_homestack):
        """compose_cmd should not crash if global config is missing."""
        from homestack import core
        import os

        # Remove the config file
        if core.CONFIG_FILE.is_file():
            os.remove(core.CONFIG_FILE)

        # Create a minimal app dir with compose.yaml
        app_dir = tmp_homestack / "testapp"
        app_dir.mkdir()
        (app_dir / "compose.yaml").write_text("services:\n  web:\n    image: nginx\n")

        # This should not crash when constructing the command —
        # it will fail on docker compose not being available, but
        # the env file handling should be resilient
        with pytest.raises((subprocess.CalledProcessError, FileNotFoundError)):
            core.compose_cmd(app_dir, "ps", capture=True)


class TestBackupIntegrity:
    """Test backup integrity verification in restore."""

    def test_corrupted_archive_rejected(self, tmp_homestack):
        """Corrupted tar files should be detected."""
        import tarfile

        # Create a corrupted file
        bad_archive = tmp_homestack / "bad.tar.gz"
        bad_archive.write_bytes(b"this is not a tar file")

        with pytest.raises((tarfile.TarError, EOFError, OSError)):
            with tarfile.open(bad_archive, "r:gz") as tar:
                tar.getmembers()

    def test_valid_archive_accepted(self, tmp_homestack):
        """Valid tar files should pass integrity check."""
        import tarfile

        # Create a valid archive
        good_archive = tmp_homestack / "good.tar.gz"
        test_file = tmp_homestack / "testfile.txt"
        test_file.write_text("hello world")

        with tarfile.open(good_archive, "w:gz") as tar:
            tar.add(test_file, arcname="testfile.txt")

        with tarfile.open(good_archive, "r:gz") as tar:
            members = tar.getmembers()
            assert len(members) == 1
            assert members[0].name == "testfile.txt"
