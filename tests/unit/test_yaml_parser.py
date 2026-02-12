"""Unit tests for homestack.yaml_parser module."""

from pathlib import Path

import pytest

from homestack.yaml_parser import (
    yaml_get,
    yaml_get_array,
    parse_secrets,
    parse_health_checks,
    parse_exec_checks,
    get_startup_time,
    load_yaml,
)


FIXTURES = Path(__file__).parent.parent / "fixtures"
SAMPLE = str(FIXTURES / "sample.yaml")
NOSECRETS = str(FIXTURES / "nosecrets.yaml")


# --- yaml_get ---

class TestYamlGet:
    def test_scalar_string(self):
        assert yaml_get(SAMPLE, "name") == "testapp"

    def test_display_name_with_spaces(self):
        assert yaml_get(SAMPLE, "display_name") == "Test App"

    def test_integer_port(self):
        assert yaml_get(SAMPLE, "port") == "18080"

    def test_integer_priority(self):
        assert yaml_get(SAMPLE, "priority") == "50"

    def test_url_value(self):
        assert yaml_get(SAMPLE, "url") == "https://example.com"

    def test_missing_key_returns_empty(self):
        assert yaml_get(SAMPLE, "nonexistent_key") == ""

    def test_backup_strategy(self):
        assert yaml_get(SAMPLE, "backup_strategy") == "stop"


# --- yaml_get_array ---

class TestYamlGetArray:
    def test_inline_array_two_items(self):
        assert yaml_get_array(SAMPLE, "networks") == ["test-net", "proxy"]

    def test_inline_appdata_dirs(self):
        assert yaml_get_array(SAMPLE, "appdata_dirs") == ["testapp", "testapp-db"]

    def test_inline_media_dirs(self):
        assert yaml_get_array(SAMPLE, "media_dirs") == ["Movies", "Downloads"]

    def test_empty_array(self):
        assert yaml_get_array(NOSECRETS, "networks") == []

    def test_missing_key(self):
        assert yaml_get_array(NOSECRETS, "nonexistent") == []


# --- parse_secrets ---

class TestParseSecrets:
    def test_three_secrets(self):
        secrets = parse_secrets(SAMPLE)
        assert len(secrets) == 3

    def test_first_secret_key(self):
        secrets = parse_secrets(SAMPLE)
        assert secrets[0].key == "DB_PASSWORD"

    def test_first_secret_generate(self):
        secrets = parse_secrets(SAMPLE)
        assert secrets[0].generate is True

    def test_first_secret_length(self):
        secrets = parse_secrets(SAMPLE)
        assert secrets[0].length == 24

    def test_second_secret_has_default(self):
        secrets = parse_secrets(SAMPLE)
        assert secrets[1].key == "DB_USERNAME"
        assert secrets[1].default == "testuser"
        assert secrets[1].generate is False

    def test_third_secret_api_key(self):
        secrets = parse_secrets(SAMPLE)
        assert secrets[2].key == "API_KEY"
        assert secrets[2].generate is True
        assert secrets[2].length == 64

    def test_no_secrets(self):
        secrets = parse_secrets(NOSECRETS)
        assert secrets == []


# --- load_yaml ---

class TestLoadYaml:
    def test_load_returns_dict(self):
        data = load_yaml(SAMPLE)
        assert isinstance(data, dict)
        assert data["name"] == "testapp"

    def test_missing_file_returns_empty(self):
        data = load_yaml("/nonexistent/file.yaml")
        assert data == {}
