"""Unit tests for homestack.secrets module."""

import os
import stat
from pathlib import Path

import pytest

from homestack.secrets import generate_password, generate_secrets_file, append_new_secrets
from homestack.yaml_parser import parse_secrets


FIXTURES = Path(__file__).parent.parent / "fixtures"
SAMPLE = str(FIXTURES / "sample.yaml")
NOSECRETS = str(FIXTURES / "nosecrets.yaml")


class TestGeneratePassword:
    def test_default_length(self):
        pw = generate_password()
        assert len(pw) == 32

    def test_custom_length(self):
        pw = generate_password(16)
        assert len(pw) == 16

    def test_alphanumeric_only(self):
        pw = generate_password(100)
        assert pw.isalnum()

    def test_different_each_time(self):
        a = generate_password()
        b = generate_password()
        assert a != b


class TestGenerateSecretsFile:
    def test_creates_file(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(SAMPLE, str(output), interactive=False)
        assert output.is_file()

    def test_file_permissions(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(SAMPLE, str(output), interactive=False)
        mode = stat.S_IMODE(output.stat().st_mode)
        assert mode == 0o600

    def test_contains_all_keys(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(SAMPLE, str(output), interactive=False)
        content = output.read_text()
        assert "DB_PASSWORD=" in content
        assert "DB_USERNAME=" in content
        assert "API_KEY=" in content

    def test_default_value_used(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(SAMPLE, str(output), interactive=False)
        content = output.read_text()
        assert "DB_USERNAME=testuser" in content

    def test_generated_passwords_correct_length(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(SAMPLE, str(output), interactive=False)
        content = output.read_text()
        for line in content.splitlines():
            if line.startswith("DB_PASSWORD="):
                pw = line.split("=", 1)[1]
                assert len(pw) == 24
            elif line.startswith("API_KEY="):
                pw = line.split("=", 1)[1]
                assert len(pw) == 64

    def test_nosecrets_creates_empty_file(self, tmp_homestack):
        output = tmp_homestack / "secrets.env"
        generate_secrets_file(NOSECRETS, str(output), interactive=False)
        content = output.read_text().strip()
        # Should be empty or just a comment
        for line in content.splitlines():
            assert line.startswith("#") or line == ""


class TestAppendNewSecrets:
    def test_adds_missing_key(self, tmp_homestack):
        secrets_file = tmp_homestack / "secrets.env"
        secrets_file.write_text("DB_PASSWORD=existing123\n")
        secrets_file.chmod(0o600)

        append_new_secrets(SAMPLE, str(secrets_file), interactive=False)
        content = secrets_file.read_text()
        # Should still have original password
        assert "DB_PASSWORD=existing123" in content
        # Should have new keys
        assert "DB_USERNAME=" in content
        assert "API_KEY=" in content

    def test_does_not_overwrite_existing(self, tmp_homestack):
        secrets_file = tmp_homestack / "secrets.env"
        secrets_file.write_text("DB_PASSWORD=myoriginal\nDB_USERNAME=myuser\n")
        secrets_file.chmod(0o600)

        append_new_secrets(SAMPLE, str(secrets_file), interactive=False)
        content = secrets_file.read_text()
        assert "DB_PASSWORD=myoriginal" in content
        assert "DB_USERNAME=myuser" in content
