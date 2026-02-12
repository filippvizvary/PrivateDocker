"""HomeStack — SQLite database layer.

Uses parameterized queries (``?`` placeholders) for safety.
Same 5-table schema as the Bash version.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from homestack import core

# ---------------------------------------------------------------------------
# Connection helper
# ---------------------------------------------------------------------------

def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(str(core.DB_FILE))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    return conn


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


# ---------------------------------------------------------------------------
# Schema initialisation
# ---------------------------------------------------------------------------

_SCHEMA = """\
CREATE TABLE IF NOT EXISTS apps (
  name              TEXT PRIMARY KEY,
  installed_version TEXT NOT NULL,
  catalog_version   TEXT,
  installed_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT,
  status            TEXT NOT NULL DEFAULT 'installed'
);

CREATE TABLE IF NOT EXISTS config_overrides (
  app               TEXT NOT NULL,
  key               TEXT NOT NULL,
  value             TEXT,
  is_user_modified  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (app, key)
);

CREATE TABLE IF NOT EXISTS backups (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  app               TEXT NOT NULL,
  path              TEXT NOT NULL,
  size_bytes        INTEGER,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  type              TEXT NOT NULL DEFAULT 'full'
);

CREATE TABLE IF NOT EXISTS health (
  app               TEXT NOT NULL,
  container         TEXT NOT NULL,
  status            TEXT,
  checked_at        TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (app, container)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp         TEXT NOT NULL DEFAULT (datetime('now')),
  action            TEXT NOT NULL,
  app               TEXT,
  detail            TEXT,
  exit_code         INTEGER
);
"""


def db_init() -> None:
    """Create all tables if they don't exist."""
    core.DB_FILE.parent.mkdir(parents=True, exist_ok=True)
    with _connect() as conn:
        conn.executescript(_SCHEMA)


# ---------------------------------------------------------------------------
# App state
# ---------------------------------------------------------------------------

def db_set_installed(app: str, version: str) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO apps (name, installed_version, installed_at, status) "
            "VALUES (?, ?, ?, 'installed')",
            (app, version, _now()),
        )


def db_set_catalog_version(app: str, version: str) -> None:
    with _connect() as conn:
        conn.execute(
            "UPDATE apps SET catalog_version = ? WHERE name = ?",
            (version, app),
        )


def db_set_updated(app: str, version: str) -> None:
    with _connect() as conn:
        conn.execute(
            "UPDATE apps SET installed_version = ?, updated_at = ? WHERE name = ?",
            (version, _now(), app),
        )


def db_remove_app(app: str) -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM apps WHERE name = ?", (app,))
        conn.execute("DELETE FROM config_overrides WHERE app = ?", (app,))
        conn.execute("DELETE FROM health WHERE app = ?", (app,))


def db_get_installed_version(app: str) -> str:
    with _connect() as conn:
        row = conn.execute(
            "SELECT installed_version FROM apps WHERE name = ?", (app,)
        ).fetchone()
    return row[0] if row else ""


def db_get_catalog_version(app: str) -> str:
    with _connect() as conn:
        row = conn.execute(
            "SELECT catalog_version FROM apps WHERE name = ?", (app,)
        ).fetchone()
    return row[0] if row else ""


def db_is_installed(app: str) -> bool:
    with _connect() as conn:
        row = conn.execute(
            "SELECT COUNT(*) FROM apps WHERE name = ?", (app,)
        ).fetchone()
    return bool(row and row[0] > 0)


def db_get_install_date(app: str) -> str:
    with _connect() as conn:
        row = conn.execute(
            "SELECT installed_at FROM apps WHERE name = ?", (app,)
        ).fetchone()
    return row[0] if row else ""


# ---------------------------------------------------------------------------
# Config tracking
# ---------------------------------------------------------------------------

def db_track_config_defaults(app: str, config_file: str | Path) -> None:
    """Store default config key-value pairs on install.

    Uses INSERT OR IGNORE so existing user-modified flags are preserved
    (bug fix: Bash version used INSERT OR REPLACE which reset the flag).
    """
    path = Path(config_file)
    if not path.is_file():
        return
    with _connect() as conn:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            value = value.strip().strip("\"'")
            conn.execute(
                "INSERT OR IGNORE INTO config_overrides (app, key, value, is_user_modified) "
                "VALUES (?, ?, ?, 0)",
                (app, key.strip(), value),
            )


def db_update_config_default(app: str, key: str, value: str) -> None:
    """Update a stored default value *only if* the user hasn't modified it."""
    with _connect() as conn:
        conn.execute(
            "UPDATE config_overrides SET value = ? "
            "WHERE app = ? AND key = ? AND is_user_modified = 0",
            (value, app, key),
        )


def db_is_config_modified(app: str, key: str, current_value: str) -> bool:
    """Return True if the user has changed a config key from its default."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT value FROM config_overrides WHERE app = ? AND key = ?",
            (app, key),
        ).fetchone()
    if row is None:
        # Key not tracked — treat as user-modified (don't overwrite)
        return True
    return current_value != row[0]


def db_mark_config_modified(app: str, key: str, value: str) -> None:
    with _connect() as conn:
        conn.execute(
            "UPDATE config_overrides SET value = ?, is_user_modified = 1 "
            "WHERE app = ? AND key = ?",
            (value, app, key),
        )


def db_get_modified_configs(app: str) -> list[tuple[str, str]]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT key, value FROM config_overrides WHERE app = ? AND is_user_modified = 1",
            (app,),
        ).fetchall()
    return [(r[0], r[1]) for r in rows]


# ---------------------------------------------------------------------------
# Backup tracking
# ---------------------------------------------------------------------------

def db_record_backup(app: str, path: str, size: int, backup_type: str = "full") -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT INTO backups (app, path, size_bytes, type) VALUES (?, ?, ?, ?)",
            (app, path, size, backup_type),
        )


def db_list_backups(app: str) -> list[dict]:
    """Return backups for *app* ordered newest first."""
    with _connect() as conn:
        rows = conn.execute(
            "SELECT id, path, size_bytes, created_at, type FROM backups "
            "WHERE app = ? ORDER BY created_at DESC",
            (app,),
        ).fetchall()
    return [dict(r) for r in rows]


def db_list_all_backups() -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT id, app, path, size_bytes, created_at, type FROM backups "
            "ORDER BY created_at DESC"
        ).fetchall()
    return [dict(r) for r in rows]


def db_remove_backup(backup_id: int) -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM backups WHERE id = ?", (backup_id,))


# ---------------------------------------------------------------------------
# Health tracking
# ---------------------------------------------------------------------------

def db_update_health(app: str, container: str, status: str) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO health (app, container, status, checked_at) "
            "VALUES (?, ?, ?, ?)",
            (app, container, status, _now()),
        )


def db_get_health(app: str) -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT container, status, checked_at FROM health WHERE app = ?",
            (app,),
        ).fetchall()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

def db_log_action(action: str, app: str = "", detail: str = "",
                  exit_code: int = 0) -> None:
    try:
        with _connect() as conn:
            conn.execute(
                "INSERT INTO audit_log (action, app, detail, exit_code) "
                "VALUES (?, ?, ?, ?)",
                (action, app, detail, exit_code),
            )
    except Exception:
        pass  # Never let audit logging crash the CLI


def db_get_audit_log(limit: int = 20) -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT timestamp, action, app, detail, exit_code FROM audit_log "
            "ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]
