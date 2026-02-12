"""Unit tests for homestack.core module."""

import os
from pathlib import Path

import pytest

from homestack import core


class TestPaths:
    def test_homestack_dir_from_env(self, tmp_homestack):
        assert core.HOMESTACK_DIR == tmp_homestack

    def test_installed_dir(self, tmp_homestack):
        assert core.INSTALLED_DIR == tmp_homestack / "installed"

    def test_db_file(self, tmp_homestack):
        assert core.DB_FILE == tmp_homestack / "homestack.db"


class TestValidatePathComponent:
    def test_valid(self):
        assert core.validate_path_component("myapp") is True

    def test_rejects_empty(self):
        assert core.validate_path_component("") is False

    def test_rejects_slash(self):
        assert core.validate_path_component("a/b") is False

    def test_rejects_dotdot(self):
        assert core.validate_path_component("..") is False

    def test_rejects_embedded_dotdot(self):
        assert core.validate_path_component("foo/../bar") is False


class TestCheckPort:
    def test_available_port(self):
        # Port 59999 should be available on test machines
        assert core.check_port_available(59999) is True


class TestLocking:
    def test_acquire_release(self, tmp_homestack):
        core.acquire_lock()
        core.release_lock()

    def test_context_manager(self, tmp_homestack):
        with core.homestack_lock():
            pass  # Should acquire and release


class TestIsInstalled:
    def test_not_installed(self, tmp_homestack):
        assert core.is_installed("nonexistent") is False

    def test_installed(self, tmp_homestack):
        app_dir = tmp_homestack / "installed" / "myapp"
        app_dir.mkdir(parents=True)
        (app_dir / "app.yaml").write_text("name: myapp\n")
        assert core.is_installed("myapp") is True


class TestEnsureDir:
    def test_creates_directory(self, tmp_homestack):
        target = tmp_homestack / "newdir" / "sub"
        core.ensure_dir(target)
        assert target.is_dir()
