"""Unit tests for homestack.db module."""

import sqlite3
from pathlib import Path

import pytest

from homestack import db


class TestDbInit:
    def test_creates_all_tables(self, db_init):
        conn = sqlite3.connect(str(db_init / "homestack.db"))
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
        conn.close()
        table_names = {t[0] for t in tables}
        assert "apps" in table_names
        assert "config_overrides" in table_names
        assert "backups" in table_names
        assert "health" in table_names
        assert "audit_log" in table_names

    def test_idempotent(self, db_init):
        # Running db_init again should not fail
        db.db_init()


class TestAppLifecycle:
    def test_set_and_get_version(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        assert db.db_get_installed_version("testapp") == "1.0.0"

    def test_is_installed_true(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        assert db.db_is_installed("testapp") is True

    def test_is_installed_false(self, db_init):
        assert db.db_is_installed("nonexistent") is False

    def test_get_install_date(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        date = db.db_get_install_date("testapp")
        assert date is not None
        # ISO timestamp starts with YYYY
        assert date[:2] == "20"

    def test_catalog_version_roundtrip(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        db.db_set_catalog_version("testapp", "2.0.0")
        assert db.db_get_catalog_version("testapp") == "2.0.0"

    def test_update_version(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        db.db_set_updated("testapp", "1.1.0")
        assert db.db_get_installed_version("testapp") == "1.1.0"

    def test_remove_app(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        db.db_remove_app("testapp")
        assert db.db_is_installed("testapp") is False

    def test_remove_cleans_related_data(self, db_init):
        db.db_set_installed("testapp", "1.0.0")
        db.db_update_health("testapp", "container1", "running")
        db.db_remove_app("testapp")
        health = db.db_get_health("testapp")
        assert health == []


class TestConfigOverrides:
    def test_track_defaults(self, db_init):
        config = db_init / "test_config.env"
        config.write_text("KEY1=val1\nKEY2=val2\n")
        db.db_track_config_defaults("testapp", str(config))
        # Not modified yet
        assert db.db_is_config_modified("testapp", "KEY1", "val1") is False

    def test_mark_modified(self, db_init):
        config = db_init / "test_config.env"
        config.write_text("KEY1=val1\n")
        db.db_track_config_defaults("testapp", str(config))
        db.db_mark_config_modified("testapp", "KEY1", "newval")
        # After modifying, the stored value is "newval"
        # Checking with original default should show it's modified
        assert db.db_is_config_modified("testapp", "KEY1", "val1") is True

    def test_insert_or_ignore_preserves_modified(self, db_init):
        """Bug fix: INSERT OR IGNORE must not reset is_user_modified."""
        config = db_init / "test_config.env"
        config.write_text("KEY1=val1\n")
        db.db_track_config_defaults("testapp", str(config))
        db.db_mark_config_modified("testapp", "KEY1", "userval")
        # Track again — INSERT OR IGNORE should not replace existing row
        config.write_text("KEY1=val2\n")
        db.db_track_config_defaults("testapp", str(config))
        # The stored value should still be "userval", not "val2"
        # Checking with "val1" (original) should show modified
        assert db.db_is_config_modified("testapp", "KEY1", "val1") is True


class TestBackups:
    def test_record_and_list(self, db_init):
        db.db_record_backup("testapp", "/tmp/test.tar.gz", 1024, "config")
        backups = db.db_list_backups("testapp")
        assert len(backups) == 1
        assert backups[0]["path"] == "/tmp/test.tar.gz"
        assert backups[0]["size_bytes"] == 1024

    def test_remove_backup(self, db_init):
        db.db_record_backup("testapp", "/tmp/test.tar.gz", 1024, "config")
        backups = db.db_list_backups("testapp")
        db.db_remove_backup(backups[0]["id"])
        assert db.db_list_backups("testapp") == []


class TestHealth:
    def test_update_and_get(self, db_init):
        db.db_update_health("testapp", "container1", "running")
        health = db.db_get_health("testapp")
        assert len(health) == 1
        assert health[0]["container"] == "container1"
        assert health[0]["status"] == "running"


class TestAuditLog:
    def test_log_and_retrieve(self, db_init):
        db.db_log_action("install", "testapp", "Installed v1.0")
        entries = db.db_get_audit_log(10)
        assert len(entries) >= 1
        assert entries[0]["action"] == "install"
        assert entries[0]["app"] == "testapp"

    def test_log_never_crashes(self, db_init):
        # Even with unusual chars
        db.db_log_action("error", "", "O'Malley's error; DROP TABLE apps;")
        entries = db.db_get_audit_log(10)
        assert len(entries) >= 1
