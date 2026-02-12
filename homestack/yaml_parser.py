"""HomeStack — YAML parser using PyYAML.

Replaces the fragile grep/sed/awk parser with proper YAML parsing.
All functions accept a file path and return typed Python objects.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


def load_yaml(filepath: str | Path) -> dict[str, Any]:
    """Load and return a YAML file as a dict.

    Returns an empty dict if the file does not exist or is not valid YAML.
    """
    try:
        with open(filepath) as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError):
        return {}
    return data if isinstance(data, dict) else {}


def yaml_get(filepath: str | Path, key: str) -> str:
    """Get a scalar value from a YAML file by top-level key.

    Returns the value as a string, or empty string if not found.
    """
    data = load_yaml(filepath)
    val = data.get(key)
    if val is None:
        return ""
    return str(val)


def yaml_get_array(filepath: str | Path, key: str) -> list[str]:
    """Get a list value from a YAML file by top-level key.

    Returns an empty list if the key is missing or the value is empty/[].
    """
    data = load_yaml(filepath)
    val = data.get(key)
    if not val:
        return []
    if isinstance(val, list):
        return [str(v) for v in val if v is not None and str(v).strip()]
    return []


# ---------------------------------------------------------------------------
# Structured secret/health-check parsing
# ---------------------------------------------------------------------------

@dataclass
class SecretDef:
    """A single secret definition from app.yaml."""
    key: str
    prompt: str = ""
    default: str = ""
    generate: bool = False
    length: int = 32


@dataclass
class HealthCheck:
    """HTTP health-check entry from test.yaml."""
    url: str
    method: str = "GET"
    expected_status: int = 200
    body_contains: str = ""
    timeout: int = 10


@dataclass
class ExecCheck:
    """Container exec check entry from test.yaml."""
    container: str
    command: str
    expected_output: str = ""


def parse_secrets(filepath: str | Path) -> list[SecretDef]:
    """Parse the ``secrets:`` block from an app.yaml file."""
    data = load_yaml(filepath)
    raw = data.get("secrets")
    if not raw or not isinstance(raw, list):
        return []
    result: list[SecretDef] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        result.append(SecretDef(
            key=str(entry.get("key", "")),
            prompt=str(entry.get("prompt", "")),
            default=str(entry.get("default", "")),
            generate=bool(entry.get("generate", False)),
            length=int(entry.get("length", 32)),
        ))
    return result


def parse_health_checks(filepath: str | Path) -> list[HealthCheck]:
    """Parse ``health_checks:`` from a test.yaml file."""
    data = load_yaml(filepath)
    raw = data.get("health_checks")
    if not raw or not isinstance(raw, list):
        return []
    result: list[HealthCheck] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        result.append(HealthCheck(
            url=str(entry.get("url", "")),
            method=str(entry.get("method", "GET")),
            expected_status=int(entry.get("expected_status", 200)),
            body_contains=str(entry.get("body_contains", "")),
            timeout=int(entry.get("timeout", 10)),
        ))
    return result


def parse_exec_checks(filepath: str | Path) -> list[ExecCheck]:
    """Parse ``exec_checks:`` from a test.yaml file."""
    data = load_yaml(filepath)
    raw = data.get("exec_checks")
    if not raw or not isinstance(raw, list):
        return []
    result: list[ExecCheck] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        result.append(ExecCheck(
            container=str(entry.get("container", "")),
            command=str(entry.get("command", "")),
            expected_output=str(entry.get("expected_output", "")),
        ))
    return result


def get_startup_time(filepath: str | Path) -> int:
    """Return the ``startup_time`` value from a test.yaml, default 30."""
    data = load_yaml(filepath)
    return int(data.get("startup_time", 30))
