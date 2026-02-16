# HomeStack Developer Guide

> A complete reference for every file, function, class, and data flow in the HomeStack project.  
> Written for new contributors who want to understand how the entire system works.
>
> **Reading order:** This guide follows the actual execution flow of the program — from
> the moment you type `homestack` on the command line, through every module it touches,
> all the way to the command that runs. Read it top-to-bottom and you'll learn the
> codebase in the same order the code itself runs.

---

## Table of Contents

**Part 1 — Overview**

1. [Project Overview](#1-project-overview)
2. [Repository Map](#2-repository-map)
3. [How the Two Repos Work Together](#3-how-the-two-repos-work-together)

**Part 2 — The Execution Path (read in this order)**

4. [Shell Wrapper — `bin/homestack`](#4-shell-wrapper) ← *you start here when you type `homestack`*
5. [Package Marker — `homestack/__init__.py`](#5-package-marker) ← *Python discovers the package*
6. [Module Entry — `homestack/__main__.py`](#6-module-entry) ← *`python -m homestack` lands here*
7. [CLI Entry Point — `homestack/cli.py`](#7-cli-entry-point) ← *Click group, command dispatch, `db_init()`*
8. [Core Module — `homestack/core.py`](#8-core-module) ← *foundation: paths, logging, locking, `compose_cmd`*
9. [Database Module — `homestack/db.py`](#9-database-module) ← *SQLite state tracking, initialized on every run*
10. [YAML Parser — `homestack/yaml_parser.py`](#10-yaml-parser) ← *reads app.yaml & test.yaml (no internal deps)*
11. [Registry Module — `homestack/registry.py`](#11-registry-module) ← *Git catalog sync (needed before install)*
12. [Secrets Module — `homestack/secrets.py`](#12-secrets-module) ← *generates secrets.env during install*
13. [Health Check Module — `homestack/health.py`](#13-health-check-module) ← *post-install/update verification*

**Part 3 — Commands (the things you actually run)**

14. [Command Files — `homestack/commands/`](#14-command-files)
    - [install.py](#141-installpy) ← *the most complex command; uses every module*
    - [update.py](#142-updatepy)
    - [remove.py](#143-removepy)
    - [backup.py](#144-backuppy)
    - [restore.py](#145-restorepy)
    - [start.py / stop.py / restart.py](#146-startpy--stoppy--restartpy)
    - [config.py](#147-configpy)
    - [status.py](#148-statuspy)
    - [list.py](#149-listpy)
    - [search.py](#1410-searchpy)
    - [catalog.py](#1411-catalogpy)
    - [logs.py](#1412-logspy)
    - [exec.py](#1413-execpy)
    - [doctor.py](#1414-doctorpy)

**Part 4 — Supporting Files**

15. [Global Config — `config/homestack.env`](#15-global-config)
16. [Build Configuration — `pyproject.toml`](#16-build-configuration)
17. [Setup Script — `setup.sh`](#17-setup-script)

**Part 5 — Cross-Cutting Concepts**

18. [Environment Variable Stacking](#18-environment-variable-stacking)
19. [Locking and Concurrency](#19-locking-and-concurrency)
20. [Error Handling Patterns](#20-error-handling-patterns)

**Part 6 — Testing**

21. [Test Suite](#21-test-suite)
    - [conftest.py — Fixtures](#211-conftestpy--fixtures)
    - [test_core.py](#212-test_corepy)
    - [test_db.py](#213-test_dbpy)
    - [test_yaml_parser.py](#214-test_yaml_parserpy)
    - [test_secrets.py](#215-test_secretspy)
    - [test_registry.py](#216-test_registrypy)
    - [Test Fixtures (YAML files)](#217-test-fixtures-yaml-files)

**Part 7 — How-To Guides**

22. [End-to-End Data Flows](#22-end-to-end-data-flows)
23. [Adding a New Command — Step by Step](#23-adding-a-new-command)
24. [Adding a New Database Table — Step by Step](#24-adding-a-new-database-table)

---

## 1. Project Overview

HomeStack is a Python CLI tool that manages self-hosted Docker Compose applications on a single Linux server. It provides:

- **Install** apps from a Git-based catalog
- **Update** apps with smart config merging
- **Backup/Restore** with rotation and integrity verification
- **Start/Stop/Restart** with priority ordering
- **Health checks** after install and update
- **Config management** with user-modification tracking
- **Audit logging** for all operations

The system is split across two repositories:

| Repo | Purpose |
|------|---------|
| `homestack` | The Python CLI tool (this repo) |
| `homestack-apps` | The app catalog — YAML + Docker Compose definitions |

### Technology Stack

- **Python 3.9+** with Click for CLI
- **SQLite** (WAL mode) for state tracking
- **PyYAML** for configuration parsing
- **Docker Compose v2** for container orchestration
- **Git** for catalog distribution
- **flock** for process-level concurrency control

---

## 2. Repository Map

```
homestack/                          ← project root
├── bin/homestack                   ← shell wrapper (activates venv, delegates to Python)
├── homestack/                      ← Python package
│   ├── __init__.py                 ← version string ("0.3.0")
│   ├── __main__.py                 ← enables `python -m homestack`
│   ├── cli.py                      ← Click group, command registration
│   ├── core.py                     ← paths, logging, locking, compose_cmd
│   ├── db.py                       ← SQLite abstraction (5 tables)
│   ├── registry.py                 ← Git catalog management
│   ├── secrets.py                  ← password generation, secrets.env management
│   ├── yaml_parser.py              ← YAML parsing with typed dataclasses
│   ├── health.py                   ← HTTP + exec health checks
│   └── commands/                   ← one file per CLI command
│       ├── __init__.py             ← empty
│       ├── install.py              ← `homestack install <app>`
│       ├── update.py               ← `homestack update [app]`
│       ├── remove.py               ← `homestack remove <app>`
│       ├── backup.py               ← `homestack backup <app>`
│       ├── restore.py              ← `homestack restore <app>`
│       ├── start.py                ← `homestack start [app]`
│       ├── stop.py                 ← `homestack stop [app]`
│       ├── restart.py              ← `homestack restart [app]`
│       ├── config.py               ← `homestack config <subcommand> <app>`
│       ├── status.py               ← `homestack status [app]`
│       ├── list.py                 ← `homestack list`
│       ├── search.py               ← `homestack search [query]`
│       ├── catalog.py              ← `homestack catalog [update|list]`
│       ├── logs.py                 ← `homestack logs <app>`
│       ├── exec.py                 ← `homestack exec <app> <cmd>`
│       └── doctor.py               ← `homestack doctor`
├── config/
│   └── homestack.env               ← global env vars (paths, TZ, UID/GID)
├── setup.sh                        ← first-run interactive installer
├── pyproject.toml                  ← build config + dependencies
├── installed/                      ← per-app runtime dirs (created by install)
├── AppData/                        ← persistent container data (bind mounts)
├── Backups/                        ← tar archives
├── Media/                          ← shared media library
├── .cache/homestack-apps/          ← cloned catalog repo
├── homestack.db                    ← SQLite database
├── .lock                           ← flock file
└── tests/                          ← pytest test suite
    ├── conftest.py                 ← shared fixtures
    ├── fixtures/                   ← YAML test data
    │   ├── sample.yaml
    │   ├── nosecrets.yaml
    │   └── catalog/apps/           ← mock catalog
    └── unit/
        ├── test_core.py
        ├── test_db.py
        ├── test_yaml_parser.py
        ├── test_secrets.py
        └── test_registry.py
```

---

## 3. How the Two Repos Work Together

The `homestack-apps` repo is a flat catalog of app definitions. Each app lives in `apps/<appname>/` with exactly 4 files:

| File | Purpose |
|------|---------|
| `app.yaml` | Metadata: name, version, port, secrets, networks, dependencies |
| `compose.yaml` | Docker Compose service definition |
| `config.env` | Default image tags and config variables |
| `test.yaml` | Health check definitions (HTTP endpoints, exec commands) |

**The flow:**

1. `homestack catalog update` → clones/pulls `homestack-apps` to `.cache/homestack-apps/`
2. `homestack install <app>` → reads from `.cache/`, copies files to `installed/<app>/`
3. Docker Compose runs with env-file stacking: `homestack.env` → `config.env` → `secrets.env`
4. `homestack update <app>` → pulls new catalog, merges config, preserves user edits

The CLI never modifies the catalog repo. The catalog is treated as read-only source material.

---

## 4. Shell Wrapper

**File:** `bin/homestack` (26 lines)

**This is where everything starts.** When you type `homestack` on the command line, this Bash script runs first.

A Bash script that:
1. Resolves `HOMESTACK_DIR` by following symlinks to find the real install path
2. Exports `HOMESTACK_DIR` as an environment variable
3. Checks that `.venv/` exists
4. Execs `${VENV}/bin/python -m homestack "$@"` — replacing the shell process

**Symlink resolution:** Uses a loop with `readlink` to follow symlinks. This means you can symlink `bin/homestack` to `/usr/local/bin/homestack` and it will still find the correct `HOMESTACK_DIR`.

**Why this matters:** The `HOMESTACK_DIR` environment variable set here is how every Python module discovers where the project lives. Without it, `core.py` falls back to resolving from the script's own file location.

**Next stop →** Python loads the `homestack` package, starting with `__init__.py`.

---

## 5. Package Marker

**File:** `homestack/__init__.py` (4 lines)

```python
"""HomeStack — Self-hosted Docker management CLI."""
__version__ = "0.3.0"
```

This is the package marker. Python needs this file to recognize `homestack/` as an importable package. The version string lives here and is the single source of truth. It's also referenced in `pyproject.toml`.

**Next stop →** The shell wrapper called `python -m homestack`, so Python looks for `__main__.py`.

---

## 6. Module Entry

**File:** `homestack/__main__.py` (5 lines)

```python
"""Allow running as ``python -m homestack``."""
from homestack.cli import cli
cli()
```

This enables `python -m homestack` execution. It simply imports the Click group from `cli.py` and calls it. That single `cli()` call is what makes Click parse your command-line arguments and dispatch to the right subcommand.

**Next stop →** `cli.py` — the Click command group that ties everything together.

---

## 7. CLI Entry Point

**File:** `homestack/cli.py` (100 lines)

Now we're in the real Python code. This file defines the Click command group and registers all subcommands. **Every single `homestack <something>` command is registered here.**

### The full journey from terminal to code

```
User types: homestack install jellyfin
      │
      ▼
bin/homestack (shell script)
      │  resolves HOMESTACK_DIR
      │  activates .venv
      │  exec .venv/bin/python -m homestack install jellyfin
      │
      ▼
homestack/__main__.py
      │  imports cli from cli.py
      │  calls cli()
      │
      ▼
homestack/cli.py → cli() Click group
      │  calls db_init() on every invocation
      │  dispatches to registered subcommand
      │
      ▼
homestack/commands/install.py → cmd_install(app_name="jellyfin", ...)
```

### 7.1 Main Group

**`cli()` — `@click.group(invoke_without_command=True)`**

The root command group. On every invocation:
1. Calls `db.db_init()` to ensure the database schema exists *(this is why the DB module is next in our reading order)*
2. If no subcommand specified, prints help

### 7.2 Command Registration

All commands are registered via `cli.add_command()`:

```python
from homestack.commands.install import cmd_install
cli.add_command(cmd_install)
# ... repeated for all commands
```

**16 registered commands:**

| Command Name | Import Source | Lock? |
|-------------|--------------|-------|
| `install` | `commands/install.py` | Yes |
| `update` | `commands/update.py` | Yes |
| `remove` | `commands/remove.py` | Yes |
| `backup` | `commands/backup.py` | Yes |
| `restore` | `commands/restore.py` | Yes |
| `start` | `commands/start.py` | Yes |
| `stop` | `commands/stop.py` | Yes |
| `restart` | `commands/restart.py` | Yes |
| `config` | `commands/config.py` | Partial |
| `status` | `commands/status.py` | No |
| `list` | `commands/list.py` | No |
| `search` | `commands/search.py` | No |
| `catalog` | `commands/catalog.py` | No |
| `logs` | `commands/logs.py` | No |
| `exec` | `commands/exec.py` | No |
| `doctor` | `commands/doctor.py` | No |
| `log` | Inline in `cli.py` | No |

### 7.3 Inline `log` Command

**`cmd_log(limit: int)` — `@cli.command("log")`**

Too small for its own file. Displays audit log entries with color coding. Takes a `limit` argument (default 20).

**Now that we know cli.py calls `db_init()` and dispatches to commands, we need to understand the foundation modules that every command relies on. The most fundamental is `core.py`.**

---

## 8. Core Module

**File:** `homestack/core.py` (248 lines)

This is the foundational utility module — **every other module imports from here.** You need to understand this file before anything else makes sense. It provides path constants, colored logging, file locking, Docker Compose execution, and app discovery.

### 8.1 Path Resolution

The entire system's directory layout is derived from a single root: `HOMESTACK_DIR`.

**`_resolve_homestack_dir() → Path`**

Determines the project root directory. Resolution order:
1. `HOMESTACK_DIR` environment variable (set by `bin/homestack` or test fixtures)
2. Fallback: grandparent of `core.py` (i.e., `homestack/homestack/core.py` → `homestack/` → project root)

**Module-level path constants:**

These are set at import time and recalculated by `refresh_paths()`:

| Constant | Value | Description |
|----------|-------|-------------|
| `HOMESTACK_DIR` | `_resolve_homestack_dir()` | Project root |
| `INSTALLED_DIR` | `HOMESTACK_DIR / "installed"` | Per-app runtime directories |
| `CONFIG_DIR` | `HOMESTACK_DIR / "config"` | Global config directory |
| `CONFIG_FILE` | `CONFIG_DIR / "homestack.env"` | Global environment file |
| `APPDATA_DIR` | `HOMESTACK_DIR / "AppData"` | Persistent container data |
| `BACKUPS_DIR` | `HOMESTACK_DIR / "Backups"` | Backup archives |
| `MEDIA_DIR` | `HOMESTACK_DIR / "Media"` | Shared media library |
| `DB_FILE` | `HOMESTACK_DIR / "homestack.db"` | SQLite database |
| `LOCK_FILE` | `HOMESTACK_DIR / ".lock"` | Process lock file |
| `CACHE_DIR` | `HOMESTACK_DIR / ".cache" / "homestack-apps"` | Cloned catalog repo |
| `APPS_DIR` | `CACHE_DIR / "apps"` | App definitions in catalog |

**`refresh_paths() → None`**

Re-derives all path globals from the current `HOMESTACK_DIR` environment variable. This is critical for testing — the `tmp_homestack` fixture sets `HOMESTACK_DIR` to a temp directory, then calls `refresh_paths()` to redirect all operations to the test environment.

**How it works internally:** It re-calls `_resolve_homestack_dir()` and reassigns every `global` path variable.

### 8.2 Logging Helpers

Four functions provide consistent, colored terminal output matching the bash-version style:

| Function | Prefix | Color | Usage |
|----------|--------|-------|-------|
| `step(msg)` | `[*]` | Blue, bold | Progress indicator ("doing something...") |
| `success(msg)` | `[✓]` | Green, bold | Completed action |
| `warn(msg)` | `[!]` | Yellow | Non-fatal warning |
| `error(msg)` | `[✗]` | Red, bold | Fatal error (written to stderr) |

All four use `click.echo()` with `click.style()` for ANSI color codes. `error()` is the only one that sends output to stderr (via `err=True`).

**Important:** These are output-only. They do NOT call `sys.exit()`. The caller is responsible for exiting after `error()`.

### 8.3 File Locking

HomeStack uses `fcntl.flock()` for process-level mutual exclusion. This prevents two `homestack` processes from modifying the system simultaneously.

**`acquire_lock() → None`**

1. Creates `LOCK_FILE` parent directory if needed
2. Opens `.lock` with `os.open()` (O_WRONLY | O_CREAT)
3. Attempts non-blocking `flock(fd, LOCK_EX | LOCK_NB)`
4. If lock is already held → prints error message and calls `sys.exit(1)`
5. Stores the file descriptor in module-level `_lock_fd`

**`release_lock() → None`**

1. If `_lock_fd` is not None, calls `flock(fd, LOCK_UN)` then `os.close(fd)`
2. Deletes the `.lock` file with `missing_ok=True`
3. Sets `_lock_fd = None`
4. All operations wrapped in try/except to prevent crashes

**`homestack_lock` (class — context manager)**

```python
with core.homestack_lock():
    # lock is held
    do_work()
# lock is released
```

Wraps `acquire_lock()` in `__enter__` and `release_lock()` in `__exit__`. Used by every mutating command.

### 8.4 Validation Helpers

**`validate_path_component(name: str) → bool`**

Security function that prevents path traversal attacks. Returns `False` (and prints error) if:
- `name` is empty
- `name` contains `/`
- `name` contains `..`

Used when creating AppData and Media directories from app.yaml values. Without this, a malicious app.yaml could specify `appdata_dirs: ["../../etc"]`.

**`check_port_available(port: int) → bool`**

Uses `socket.connect_ex()` on `127.0.0.1:port`. Returns `True` if the port is free (connection refused), `False` if something is listening.

Used by `install.py` before starting a new app to warn about port conflicts.

### 8.5 Docker Compose Wrapper

**`compose_cmd(app_dir, *args, capture=False, check=True, quiet_err=False) → CompletedProcess`**

This is the single most important function in the codebase. **Every Docker operation goes through this function** — no command file ever calls `docker compose` directly.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `app_dir` | `str \| Path` | required | Directory containing compose.yaml |
| `*args` | `str` | — | Docker Compose subcommand + flags (e.g., `"up"`, `"-d"`) |
| `capture` | `bool` | `False` | Capture stdout/stderr instead of printing |
| `check` | `bool` | `True` | Raise `CalledProcessError` on non-zero exit |
| `quiet_err` | `bool` | `False` | Suppress stderr output |

**What it does, step by step:**

1. Converts `app_dir` to a `Path` object
2. Checks that `compose.yaml` exists in `app_dir`; raises `FileNotFoundError` if missing
3. Builds env-file flags by checking for existence of:
   - `CONFIG_FILE` (global `homestack.env`) — **only if the file exists** (resilience fix)
   - `app_dir/config.env` (app-specific config)
   - `app_dir/secrets.env` (generated secrets)
4. Constructs the command: `docker compose -f <compose.yaml> --env-file <...> <args>`
5. Runs via `subprocess.run()` with `check=False` (manual error handling)
6. If `check=True` and exit code is non-zero, prints the error and raises `CalledProcessError`
7. Returns the `CompletedProcess` object

**env-file stacking order** (last wins for duplicate keys):

```
homestack.env  →  config.env  →  secrets.env
   (global)        (app defaults)    (generated passwords)
```

This means a secret defined in `secrets.env` overrides anything in `config.env` or `homestack.env`.

### 8.6 App Discovery

**`get_installed_apps() → list[str]`**

Returns a list of installed app names, sorted by priority (lower priority number = earlier in list).

1. Iterates over `INSTALLED_DIR` subdirectories
2. For each directory that contains `app.yaml`, reads the `priority` field
3. Sorts by priority (default 50)
4. Returns just the names

This ordering is used by `start all` (start in priority order) and `stop all` (reversed).

**`is_installed(app_name: str) → bool`**

Simple check: returns `True` if `installed/<app_name>/` exists AND contains `app.yaml`.

### 8.7 Network and Directory Helpers

**`ensure_network(name: str) → None`**

1. Runs `docker network inspect <name>` to check existence
2. If not found, runs `docker network create <name>`
3. Prints success message if created

Networks are declared in `app.yaml` (e.g., `networks: [media-net]`) and referenced as `external: true` in compose.yaml.

**`ensure_dir(path: str | Path) → None`**

Equivalent to `mkdir -p`. Creates the directory and all parents, no error if it already exists.

---

## 9. Database Module

**File:** `homestack/db.py` (309 lines)

Remember how `cli.py` calls `db_init()` on every single invocation? This is the module that provides it. It's a full SQLite abstraction layer — **all database queries go through functions in this module.** No other module touches SQLite directly.

### 9.1 Connection Management

**`_connect() → sqlite3.Connection`**

Opens a new SQLite connection to `core.DB_FILE` with:
- **WAL mode** (`PRAGMA journal_mode=WAL`) — allows concurrent readers with one writer
- **Row factory** (`sqlite3.Row`) — results behave as both tuples and dicts

Every function opens its own connection via `_connect()` and uses `with conn:` context manager for automatic commit/rollback. Connections are short-lived (opened, used, closed within a single function call).

**`_now() → str`**

Returns the current UTC time formatted as `"YYYY-MM-DD HH:MM:SS"`. Used for all timestamp fields.

### 9.2 Schema

**`db_init() → None`**

Creates all 5 tables using `CREATE TABLE IF NOT EXISTS`. Called on every CLI invocation (from `cli.py`), making it safe to call repeatedly.

**5 tables:**

#### `apps` — Installed app records

```sql
CREATE TABLE apps (
    name              TEXT PRIMARY KEY,
    installed_version TEXT NOT NULL,
    catalog_version   TEXT,
    installed_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT,
    status            TEXT NOT NULL DEFAULT 'installed'
);
```

- `name`: The canonical app identifier (matches directory name)
- `installed_version`: Version string from app.yaml at time of install/update
- `catalog_version`: Latest version available in the catalog (updated by `registry_sync`)
- `installed_at` / `updated_at`: ISO timestamps
- `status`: Currently always `'installed'` (reserved for future states)

#### `config_overrides` — Config key tracking

```sql
CREATE TABLE config_overrides (
    app               TEXT NOT NULL,
    key               TEXT NOT NULL,
    value             TEXT,
    is_user_modified  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (app, key)
);
```

This table tracks every `KEY=VALUE` pair from `config.env` for each installed app. The `is_user_modified` flag distinguishes between catalog defaults and user changes.

**Purpose:** When updating an app, HomeStack needs to know which config values the user has customized (to preserve them) vs. which are still at defaults (safe to overwrite with new catalog values).

**How the flag works:**
- On install: `db_track_config_defaults()` inserts all keys with `is_user_modified = 0`
- When user runs `homestack config edit`: `db_mark_config_modified()` sets `is_user_modified = 1`
- On update: `_merge_config()` checks `db_is_config_modified()` for each key
- On reset: `config reset` sets `is_user_modified = 0`

#### `backups` — Backup records

```sql
CREATE TABLE backups (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    app        TEXT NOT NULL,
    path       TEXT NOT NULL,
    size_bytes INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    type       TEXT NOT NULL DEFAULT 'full'
);
```

- `type`: One of `"config"`, `"data"`, or `"full"`
- `path`: Absolute filesystem path to the .tar.gz file
- Used by `restore.py` to list available backups

#### `health` — Container health status

```sql
CREATE TABLE health (
    app        TEXT NOT NULL,
    container  TEXT NOT NULL,
    status     TEXT,
    checked_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (app, container)
);
```

Updated by `status.py` when it queries container states, and by `health.py` after install/update checks.

#### `audit_log` — Action history

```sql
CREATE TABLE audit_log (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    action    TEXT NOT NULL,
    app       TEXT,
    detail    TEXT,
    exit_code INTEGER
);
```

Records every significant operation (install, update, remove, backup, restore, config change, etc.). Viewable via `homestack log`.

### 9.3 App State Functions

**`db_set_installed(app: str, version: str) → None`**

`INSERT OR REPLACE` into apps table. Sets `installed_at` to current time and `status` to `'installed'`. Used at end of successful install.

**`db_set_catalog_version(app: str, version: str) → None`**

`UPDATE` the `catalog_version` field. Called by `_update_catalog_versions()` in registry.py when syncing the catalog.

**`db_set_updated(app: str, version: str) → None`**

`UPDATE` the `installed_version` and `updated_at` fields. Called after a successful update.

**`db_remove_app(app: str) → None`**

`DELETE` from `apps`, `config_overrides`, and `health` tables. Cascading cleanup — removes all state for an app.

**`db_get_installed_version(app: str) → str`**

Returns the installed version string, or empty string if not found.

**`db_get_catalog_version(app: str) → str`**

Returns the catalog version string, or empty string if not found.

**`db_is_installed(app: str) → bool`**

Returns `True` if the app exists in the `apps` table. Note: this checks the *database*, not the filesystem. `core.is_installed()` checks the filesystem.

**`db_get_install_date(app: str) → str`**

Returns the `installed_at` timestamp string.

### 9.4 Config Tracking Functions

**`db_track_config_defaults(app: str, config_file: str | Path) → None`**

Parses a `config.env` file and inserts each `KEY=VALUE` pair into `config_overrides` with `is_user_modified = 0`.

**Critical detail:** Uses `INSERT OR IGNORE` (not `INSERT OR REPLACE`). This means if a key already exists in the table (e.g., from a previous install), the existing row is preserved — including any `is_user_modified = 1` flag. This prevents re-tracking from accidentally resetting user modifications.

**`db_update_config_default(app: str, key: str, value: str) → None`**

Updates the stored default value, **but only if** `is_user_modified = 0`. This is used during updates to refresh defaults without touching user-modified values.

**`db_is_config_modified(app: str, key: str, current_value: str) → bool`**

Returns `True` if the user has changed a config key from its default. This is the function that `_merge_config()` in update.py calls for every key.

**Logic (3 cases):**
1. Key not tracked at all → return `True` (treat as modified — don't overwrite unknown values)
2. `is_user_modified` flag is `1` → return `True` (explicitly marked by `config edit`)
3. Neither flag is set → fall back to comparing `current_value != stored_value` (detects manual edits to config.env outside of `homestack config edit`)

**Bug fix note:** The original implementation only did case 3 (value comparison). This broke when `db_mark_config_modified()` stored the user's NEW value — because `current_value` would equal `stored_value` (both are the user's value), so it returned `False` (not modified). Adding the `is_user_modified` flag check (case 2) fixes this.

**`db_mark_config_modified(app: str, key: str, value: str) → None`**

Sets `is_user_modified = 1` and stores the new value. Called by `config edit`.

**`db_get_modified_configs(app: str) → list[tuple[str, str]]`**

Returns list of `(key, value)` tuples for all keys where `is_user_modified = 1`. Used by `config show` to display modification status.

### 9.5 Backup Tracking Functions

**`db_record_backup(app: str, path: str, size: int, backup_type: str) → None`**

Inserts a backup record. Called after successfully creating a tar archive.

**`db_list_backups(app: str) → list[dict]`**

Returns all backups for an app, newest first. Each dict contains: `id`, `path`, `size_bytes`, `created_at`, `type`.

**`db_list_all_backups() → list[dict]`**

Like `db_list_backups` but for all apps. Also includes the `app` field.

**`db_remove_backup(backup_id: int) → None`**

Deletes a backup record by ID. Called during backup rotation (doesn't delete the file — that's handled separately).

### 9.6 Health Tracking Functions

**`db_update_health(app: str, container: str, status: str) → None`**

`INSERT OR REPLACE` — updates the health status for a specific container. The `(app, container)` primary key means each container has exactly one health record.

**`db_get_health(app: str) → list[dict]`**

Returns all health records for an app. Each dict contains: `container`, `status`, `checked_at`.

### 9.7 Audit Log Functions

**`db_log_action(action: str, app: str = "", detail: str = "", exit_code: int = 0) → None`**

Inserts an audit log entry. **Entire function body is wrapped in try/except that passes silently.** This is intentional — audit logging must never crash the CLI, even with SQL injection-like strings or database errors.

**`db_get_audit_log(limit: int = 20) → list[dict]`**

Returns the most recent `limit` audit log entries, newest first. Each dict contains: `timestamp`, `action`, `app`, `detail`, `exit_code`.

---

## 10. YAML Parser

**File:** `homestack/yaml_parser.py` (149 lines)

**Why read this next?** This is the simplest module in the project — it has **zero internal dependencies** (only uses PyYAML and the standard library). Every other module that reads `app.yaml` or `test.yaml` goes through here. Understanding this module first makes all the others easier to follow.

Provides typed parsing of YAML configuration files using PyYAML and Python dataclasses.

### 10.1 Dataclasses

**`SecretDef`** — Represents one entry in the `secrets:` block of app.yaml

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `key` | `str` | `""` | Environment variable name (e.g., `DB_PASSWORD`) |
| `prompt` | `str` | `""` | Human-readable prompt text |
| `default` | `str` | `""` | Static default value |
| `generate` | `bool` | `False` | Whether to auto-generate a random password |
| `length` | `int` | `32` | Password length when generating |

**`HealthCheck`** — Represents one HTTP health check from test.yaml

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | `str` | `""` | Full URL to check |
| `method` | `str` | `"GET"` | HTTP method |
| `expected_status` | `int` | `200` | Expected HTTP response code |
| `body_contains` | `str` | `""` | Substring to find in response body |
| `timeout` | `int` | `10` | Request timeout in seconds |

**`ExecCheck`** — Represents one container exec check from test.yaml

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `container` | `str` | `""` | Docker service name |
| `command` | `str` | `""` | Shell command to execute |
| `expected_output` | `str` | `""` | Substring to find in stdout |

### 10.2 Loading Functions

**`load_yaml(filepath: str) → dict`**

Loads a YAML file using `yaml.safe_load()`. Returns empty dict `{}` if the file doesn't exist or is unparseable (logs warning).

**`yaml_get(filepath: str, key: str) → str`**

Gets a single top-level scalar value from a YAML file and returns it as a string. Returns `""` if the key doesn't exist.

**Important:** Converts everything to string. So `port: 8096` returns `"8096"`, not `8096`.

**`yaml_get_array(filepath: str, key: str) → list[str]`**

Gets a top-level list value from a YAML file. Returns `[]` if the key doesn't exist or the value is not a list. Each element is converted to string.

### 10.3 Parsing Functions

**`parse_secrets(filepath: str) → list[SecretDef]`**

Reads the `secrets:` key from a YAML file and converts each entry to a `SecretDef` dataclass. Returns empty list if no secrets defined.

**`parse_health_checks(filepath: str) → list[HealthCheck]`**

Reads `health_checks:` from a YAML file and converts to `HealthCheck` objects. Called by `health.py`.

**`parse_exec_checks(filepath: str) → list[ExecCheck]`**

Reads `exec_checks:` from a YAML file and converts to `ExecCheck` objects. Called by `health.py`.

**`get_startup_time(filepath: str) → int`**

Reads `startup_time:` from test.yaml. Defaults to `30` if not specified. This is how long to wait for containers to become healthy before running checks.

---

## 11. Registry Module

**File:** `homestack/registry.py` (175 lines)

**Why read this next?** Before you can install an app, you need the catalog. This module manages the local Git clone of the `homestack-apps` repository. It's the bridge between the two repos.

### 11.1 Internal Helpers

**`_repo_url() → str`**

Resolves the catalog repo URL in this order:
1. `HOMESTACK_APPS_REPO` environment variable
2. Value from `config/homestack.env` (parsed manually)
3. Default: `https://github.com/filippvizvary/homestack-apps.git`

This allows overriding the catalog source for development (e.g., point to a local directory or fork).

### 11.2 Sync Functions

**`registry_sync() → None`**

Synchronizes the local catalog clone with the remote repository.

1. If `.cache/homestack-apps/` doesn't exist: runs `git clone <url>`
2. If it exists: runs `git -C <dir> pull --ff-only`
3. After sync, calls `_update_catalog_versions()` to update DB records

Prints progress via `core.step()` and `core.success()`.

**`_update_catalog_versions() → None`**

After a catalog sync, iterates over all installed apps and checks if there's a matching entry in the catalog. If found, reads the catalog's `version` field from `app.yaml` and calls `db_set_catalog_version()` to store it. This makes version comparison available via `db_get_catalog_version()` without re-reading YAML files.

**`registry_ensure() → None`**

Ensures the catalog is available locally. If `APPS_DIR` doesn't exist, calls `registry_sync()`. Otherwise does nothing. This is called before any command that reads from the catalog (install, search, etc.).

### 11.3 Query Functions

**`registry_list() → list[dict]`**

Returns metadata for all apps in the catalog as a list of dicts. Each dict contains: `name`, `display_name`, `description`, `category`, `port`, `version`.

1. Iterates `APPS_DIR` subdirectories
2. For each directory with `app.yaml`, reads it via `yaml.safe_load()`
3. Builds and returns the list sorted by name

**`registry_find(app_name: str) → str`**

Finds an app by name and returns the absolute path to its catalog directory.

1. First tries exact match: `APPS_DIR / app_name`
2. If not found, tries case-insensitive fallback: lowercases both sides
3. Returns empty string `""` if not found

**`registry_search(query: str) → list[dict]`**

Substring search across multiple fields. Lowercases the query and checks each app's `name`, `display_name`, `description`, and `category` for substring matches.

Returns same dict format as `registry_list()`, but filtered.

---

## 12. Secrets Module

**File:** `homestack/secrets.py` (144 lines)

**Why read this next?** During installation, after the catalog files are copied, secrets need to be generated. This module handles that. It uses `yaml_parser.py` to read secret definitions from `app.yaml`.

### 12.1 Password Generation

**`generate_password(length: int = 32) → str`**

Generates a cryptographically random alphanumeric password.

- Uses `secrets.choice()` (Python's cryptographic RNG)
- Character set: `string.ascii_letters + string.digits` (a-z, A-Z, 0-9)
- No special characters — intentional, to avoid shell escaping issues in env files

### 12.2 Secrets File Creation

**`generate_secrets_file(app_yaml: str, output: str, *, interactive: bool = True) → None`**

Creates a new `secrets.env` file based on the `secrets:` block in `app.yaml`.

**Parameters:**
- `app_yaml`: Path to app.yaml
- `output`: Path where secrets.env will be written
- `interactive`: If `True`, prompts user for values. If `False`, uses defaults/generation.

**For each secret defined in app.yaml, one of three things happens:**

| Secret Config | Interactive Mode | Non-Interactive Mode |
|---------------|------------------|----------------------|
| `generate: true` | Auto-generates password, no prompt | Auto-generates password |
| `default: "value"` | Prompts with default pre-filled | Uses default silently |
| Neither | Prompts (empty default) | Writes `KEY=` (empty) |

**File security:** After writing, sets permissions to `0o600` (owner read/write only).

**Edge case handling:** If the `secrets:` block is empty or missing in app.yaml, creates an empty file with just a comment: `# No secrets for this app`.

### 12.3 Secrets Update

**`append_new_secrets(app_yaml: str, secrets_file: str, *, interactive: bool = True) → None`**

Used during `homestack update` to add new secret keys without overwriting existing ones.

1. Reads existing secrets.env into a dict
2. Parses app.yaml for secret definitions
3. For each secret key NOT already in the file:
   - If `generate: true`: auto-generates and appends
   - If `default`: uses default (or prompts in interactive mode)
4. Writes back the entire file
5. Resets permissions to `0o600`

**Critical invariant:** Existing keys are NEVER modified. Only new keys are added. This prevents updates from resetting user-configured passwords.

---

## 13. Health Check Module

**File:** `homestack/health.py` (181 lines)

**Why read this last (among the library modules)?** Health checks run at the very end of install and update — after the catalog is synced, files are copied, secrets are generated, and containers are started. This module ties together `yaml_parser.py` (to read test.yaml) and `core.compose_cmd()` (to run exec checks).

### 13.1 Orchestrator

**`run_health_checks(app_name: str, install_dir: Path) → bool`**

Main entry point. Returns `True` if all checks pass, `False` if any fail.

**Three phases:**

1. **Wait for containers** — calls `_wait_for_healthy()` with the `startup_time` from test.yaml
2. **HTTP checks** — runs each `HealthCheck` via `_run_http_check()`
3. **Exec checks** — runs each `ExecCheck` via `_run_exec_check()`

**Early returns:**
- If `test.yaml` doesn't exist in `install_dir` → returns `True` (no checks to run)
- If both `health_checks` and `exec_checks` are empty → returns `True`

### 13.2 Container Wait

**`_wait_for_healthy(install_dir: Path, timeout: int) → bool`**

Polls `docker compose ps` every 5 seconds until:
- All containers report "Up" in their status, OR
- Timeout is reached

Returns `True` if all containers came up, `False` on timeout.

**Implementation detail:** Runs `compose_cmd(install_dir, "ps", "--format", "{{.Status}}", capture=True)` and checks each line for `"up"` (case-insensitive).

### 13.3 HTTP Checks

**`_run_http_check(app_name: str, hc: HealthCheck, retries: int = 5, retry_delay: int = 3) → bool`**

Performs an HTTP request against the health check URL and validates the response.

**Retry logic:**
- Up to `retries` attempts (default 5)
- Sleeps `retry_delay` seconds between attempts (default 3)
- Only fails after all retries are exhausted

**SSL handling:** Installs a custom `ssl.SSLContext` that skips certificate verification. This is necessary because many self-hosted apps use self-signed certificates (e.g., Nextcloud on port 443).

**Redirect handling:** Installs a custom `urllib.request.HTTPRedirectHandler` that raises an error on redirects. This prevents health checks from following redirects to login pages (which would return 200 even when the app is misconfigured).

**Validation steps:**
1. Check response status code against `hc.expected_status`
2. If `hc.body_contains` is set, check that the response body contains the string

**Error handling:** Catches `urllib.error.HTTPError`, `urllib.error.URLError`, `OSError`, and generic `Exception`. All failures are logged via `core.warn()`.

### 13.4 Exec Checks

**`_run_exec_check(app_name: str, install_dir: Path, ec: ExecCheck) → bool`**

Runs a command inside a container and validates the output.

1. Calls `compose_cmd(install_dir, "exec", ec.container, "sh", "-c", ec.command, capture=True, check=False)`
2. Checks return code — non-zero means failure
3. If `ec.expected_output` is set, checks that stdout contains the string

Returns `True` if the check passes.

**Now that you understand all the library modules, you're ready for the commands — the actual things users run. Each command file pulls together the modules above to accomplish its task.**

---

## 14. Command Files

Each file in `homestack/commands/` exports exactly one Click command (or group). Every command follows the same pattern:
1. Import `core`, `db`, and any needed parsers
2. Define a Click command with decorators
3. Validate input
4. Acquire lock (if mutating)
5. Perform the operation
6. Log to audit log
7. Print success/failure

**We start with `install.py` because it's the most complex command and uses every single module** — understanding it means you understand how the whole system fits together.

### 14.1 `install.py`

**File:** `homestack/commands/install.py` (220 lines)

**Command:** `homestack install <app_name> [--skip-checks] [--defaults]`

**Options:**
- `--skip-checks`: Skip post-install health checks
- `--defaults`: Accept all defaults without prompting (forces non-interactive mode)

**Interactive detection:** `os.isatty(sys.stdin.fileno())` checks if stdin is a terminal. Combined with `--defaults`, this prevents `click.prompt()` from hanging when run via SSH or in scripts.

**Full install flow:**

```
1. Check if already installed → error if yes
2. ACQUIRE LOCK
3. registry_find(app_name) → find in catalog
4. Normalize app name to catalog's canonical name
5. Read app.yaml metadata (display_name, port, version)
6. Check depends_on → warn about missing dependencies
7. Check port availability → warn if in use
8. Create installed/<app>/ directory
9. Copy compose.yaml, app.yaml, config.env, test.yaml from catalog
10. Create Docker networks (from app.yaml networks:[])
11. Create AppData directories (from app.yaml appdata_dirs:[])
12. Pre-create volume mount paths (_precreate_volumes)
13. Create Media directories (from app.yaml media_dirs:[])
14. Generate secrets.env (generate_secrets_file)
15. Save config defaults to DB (db_track_config_defaults)
16. Start app: compose_cmd up -d
17. Run health checks (unless --skip-checks)
18. Record in DB: db_set_installed
19. Log to audit: db_log_action
20. Print success message with next-steps
21. RELEASE LOCK
```

**Rollback on failure (steps on exception):**
1. `compose_cmd("down")` — stop any partially started containers
2. `shutil.rmtree(install_dir)` — delete the installed directory
3. `db_remove_app()` — clean up database records
4. `db_log_action(..., exit_code=1)` — log the failure
5. `sys.exit(1)`

**`_precreate_volumes(compose_path: Path) → None`** (private helper)

Solves the "Docker creates directories as root" problem. When Docker encounters a bind mount for a directory that doesn't exist, it creates it owned by root. This makes the directory inaccessible to the container's non-root user.

1. Parses compose.yaml via `load_yaml()`
2. Builds a variable map: `${APPDATA}` → actual path, `${MEDIA}` → actual path
3. For each service's volume mount, extracts the host path
4. Expands `${APPDATA}/<app>/data` to the actual filesystem path
5. If the path starts with `/` and doesn't exist, creates it with `mkdir`

This way, the directories are owned by the user running `homestack`, not root.

### 14.2 `update.py`

**File:** `homestack/commands/update.py` (197 lines)

**Command:** `homestack update [app_name] [--skip-checks] [--dry-run]`

**Options:**
- `--skip-checks`: Skip post-update health checks
- `--dry-run`: Show what would be updated without making changes

**Single app update flow (`_update_app`):**

```
1. Check installed → error if not
2. Find in catalog via registry_find
3. Compare versions: installed vs catalog
4. If different:
   a. Auto-backup config (tar installed/<app>/ → Backups/<app>/)
   b. Copy new app.yaml, compose.yaml, test.yaml from catalog
   c. Smart merge config.env (_merge_config)
   d. Append new secrets (append_new_secrets)
   e. Update DB version (db_set_updated)
   f. Re-track config defaults (db_track_config_defaults)
5. Pull latest images: compose_cmd pull
6. Recreate containers: compose_cmd up -d --remove-orphans
7. Run health checks (unless --skip-checks)
8. Log to audit
```

**Dry run mode:**

When `--dry-run` is set, the command only syncs the catalog and compares versions. For each app, it prints either "(update available)" with the version change, or "(up to date)". No files are modified, no containers are touched.

**`_merge_config(app_name: str, install_dir: Path, new_config: Path) → None`** (private helper)

The smart config merge algorithm:

1. If no existing config.env → just copy the new one
2. Read current config.env into `current_values` dict
3. Copy new config as `config.env.new` (start from catalog defaults)
4. For each key in current config:
   - Call `db_is_config_modified(app, key, current_value)`
   - If modified → overwrite the key in `config.env.new` with the user's value
   - Print warning: `"Preserved user-modified config: KEY"`
5. Rename `config.env.new` → `config.env`

**Result:** New keys from the catalog are added. Updated defaults are applied. User customizations are preserved.

### 14.3 `remove.py`

**File:** `homestack/commands/remove.py` (115 lines)

**Command:** `homestack remove <app_name>`

**Flow:**

```
1. Check installed → error if not
2. ACQUIRE LOCK
3. Check reverse dependencies (other installed apps that depend on this one)
   → Warn if any, but allow continuation
4. Stop containers: compose_cmd down
5. Clean up Docker networks:
   - For each network in app.yaml, inspect it
   - If no other containers are using it, remove it
6. Ask about AppData deletion:
   - If user says yes, try shutil.rmtree
   - If PermissionError (container-owned files), fall back to:
     docker run --rm -v <path>:/cleanup busybox rm -rf /cleanup
7. Remove installed/<app>/ directory (shutil.rmtree)
8. Remove DB records (db_remove_app)
9. Log to audit
10. RELEASE LOCK
```

**Docker fallback for permissions:** Some containers create files owned by internal users (e.g., UID 999 for PostgreSQL). These files can't be deleted by the homestack user. The fallback runs a temporary `busybox` container with the AppData directory mounted, which can delete the files with root permissions inside the container.

**Reverse dependency check:** Scans all installed apps' `app.yaml` files for `depends_on` arrays that include the app being removed. If found, warns the user but doesn't block removal.

### 14.4 `backup.py`

**File:** `homestack/commands/backup.py` (165 lines)

**Command:** `homestack backup <app_name>`

**Backup strategy** (from app.yaml `backup_strategy:` field):
- `live` (default): Backup while containers are running
- `stop`: Stop containers before backup, restart after

**Flow:**

```
1. Read backup_strategy from app.yaml
2. ACQUIRE LOCK
3. If strategy is "stop":
   a. Stop containers: compose_cmd down
4. Create config backup:
   - Tar contents of installed/<app>/ → Backups/<app>/<app>_config_<timestamp>.tar.gz
5. Create data backup:
   - For each appdata_dir in app.yaml:
     - Tar AppData/<dir>/ → Backups/<app>/<app>_data_<timestamp>.tar.gz
   - Docker fallback on PermissionError (same as remove.py)
6. If strategy was "stop":
   a. Restart containers: compose_cmd up -d
7. Record both backups in DB (db_record_backup)
8. Rotate old backups (_rotate_backups)
9. Log to audit
10. RELEASE LOCK
```

**`_rotate_backups(app_name: str, backup_type: str, keep: int = 5)` → None**

Keeps only the `keep` most recent backups of each type:
1. Gets all backups from DB for this app+type
2. Sorts by creation date (newest first)
3. For backups beyond `keep`:
   - Deletes the file from disk
   - Removes the DB record (`db_remove_backup`)
4. Also scans the Backups directory for orphaned files (files not in DB) and removes them

The constant `KEEP_LAST = 5` is defined at module level.

### 14.5 `restore.py`

**File:** `homestack/commands/restore.py` (170 lines)

**Command:** `homestack restore <app_name>`

**Flow:**

```
1. Check installed → error if not
2. ACQUIRE LOCK
3. List available backups from DB (db_list_backups)
4. If no DB records, fall back to filesystem scan (Backups/<app>/*.tar.gz)
5. Display backup list with type, filename, size, date
6. Prompt user to select a backup number
7. Confirm destructive operation
8. VERIFY BACKUP INTEGRITY:
   - Open archive with tarfile.open("r:gz")
   - Call tar.getmembers() to read all headers
   - If corrupted → error and exit (no data is modified)
9. Stop the app: compose_cmd down
10. Determine backup type (from DB record or filename heuristic):
    - "_config_" in name → config backup → extract to installed/<app>/
    - "_data_" in name → data backup → extract to AppData/
    - Unknown → extract to AppData/<first_appdata_dir>
11. Restart the app: compose_cmd up -d
12. Log to audit
13. RELEASE LOCK
```

**Integrity verification:** The `tar.getmembers()` call forces reading all tar headers. If the archive is truncated or corrupted, this raises `TarError`, `EOFError`, or `OSError`. This check happens BEFORE stopping the app, so a corrupted backup won't leave the app in a stopped state.

**`_human_size(size_bytes: int) → str`** (private helper)

Converts bytes to human-readable format: `"1.5 MB"`, `"32.0 KB"`, etc.

### 14.6 `start.py` / `stop.py` / `restart.py`

**Files:** 53 / 51 / 69 lines respectively

**Commands:**
- `homestack start [app_name]` — Start one or all apps
- `homestack stop [app_name]` — Stop one or all apps
- `homestack restart [app_name]` — Restart one or all apps

**`app_name` is optional.** If omitted, the command operates on ALL installed apps.

**Priority ordering:**
- `start all`: starts apps in priority order (lower number first)
- `stop all`: stops apps in **reverse** priority order (high-priority apps stop last)
- `restart all`: stops in reverse order, then starts in forward order

**start.py `_start_one(app_name, quiet=False)`:**
1. Check installed
2. Ensure Docker networks exist
3. `compose_cmd(install_dir, "up", "-d")`
4. Log to audit (unless `quiet=True` — used in "start all" to avoid per-app logging)

**stop.py `_stop_one(app_name, quiet=False)`:**
1. Check installed
2. `compose_cmd(install_dir, "down", check=False, quiet_err=True)`
3. Log to audit

**restart.py `_restart_one(app_name)`:**
1. Check installed
2. `compose_cmd(install_dir, "down", check=False, quiet_err=True)`
3. Ensure networks
4. `compose_cmd(install_dir, "up", "-d")`
5. Log to audit

**Why `check=False` and `quiet_err=True` on stop/down?** Because `docker compose down` can fail if containers are already stopped. This shouldn't be treated as an error.

### 14.7 `config.py`

**File:** `homestack/commands/config.py` (191 lines)

**Command group:** `homestack config <subcommand>`

This is a Click **group** (not a simple command) with three subcommands for managing app configuration.

**Lock requirement:** Only the `edit` and `reset` subcommands acquire the lock. The `show` subcommand is read-only.

#### Subcommand: `show`

**`homestack config show <app>`**

Displays the current configuration from `config.env` in a formatted table.

**What it displays:**
1. Reads `installed/<app>/config.env`
2. For each `KEY=VALUE` line (skipping comments and blank lines):
   - Queries `db_get_modified_configs()` to check if the key has been modified by the user
   - Shows status as either "modified" (yellow) or "default" (green)
   - Truncates values longer than 35 characters
3. Displays in a three-column table: KEY, VALUE, STATUS

**Example output:**
```
Config — Jellyfin

  KEY                            VALUE                               STATUS
  ---                            -----                               ------
  JELLYFIN_SERVER                jellyfin/jellyfin:10.11.5           default
  JELLYFIN_PORT                  8097                                modified
```

#### Subcommand: `edit`

**`homestack config edit <app> <key> <value>`**

Updates a configuration key in `config.env` and optionally restarts the app.

**Steps:**
1. Acquires lock (mutating operation)
2. Reads current `config.env`
3. Searches for the specified key
4. If key not found → displays available keys and exits with error
5. Updates the line: `KEY=new_value` (replaces entire line)
6. Writes updated config back to file
7. Calls `db_mark_config_modified(app, key, value)` to mark as user-modified
8. Prompts user: "Restart app to apply changes?" (default: Yes)
9. If yes → runs `compose_cmd(install_dir, "up", "-d", "--remove-orphans")`
10. Logs action to audit log

**Example:**
```bash
homestack config edit jellyfin JELLYFIN_PORT 8097
```

#### Subcommand: `reset`

**`homestack config reset <app> <key>`**

Resets a configuration key to its catalog default value.

**Steps:**
1. Acquires lock (mutating operation)
2. Queries `config_overrides` table for the default value
3. If no default tracked → error (this happens if the key was added manually, not from catalog)
4. Updates `config.env` with the default value
5. Clears the `is_user_modified` flag in the database (sets to 0)
6. Logs action to audit log

**Use case:** User edited a config value, realized it broke something, wants to go back to the catalog default without manually looking it up.

**Example:**
```bash
homestack config reset jellyfin JELLYFIN_PORT
# Resets JELLYFIN_PORT back to 8096 (catalog default)
```

### 14.8 `status.py`

**File:** `homestack/commands/status.py` (82 lines)

**Command:** `homestack status [app_name]`

**No lock required** — this is a read-only operation.

**What it does:**

1. Gets list of apps to display (one or all)
2. Prints a formatted table with columns: APP, PORT, STATUS, CONTAINERS
3. For each app:
   - Runs `compose_cmd(install_dir, "ps", "--format", "{{.Name}}\t{{.Status}}", capture=True)`
   - If no output → status is "stopped" (red)
   - Parses each line's status text for color:
     - "unhealthy" → red
     - "up" or "running" → green
     - "exited" or "dead" → red
     - "restarting" → yellow
     - other → white
   - Updates health table in DB via `db_update_health()`

### 14.9 `list.py`

**File:** `homestack/commands/list.py` (43 lines)

**Command:** `homestack list`

Prints a formatted table of all installed apps with columns: NAME, CATEGORY, PORT, VERSION, INSTALLED DATE.

Gets app metadata from each app's `app.yaml` and install date from `db_get_install_date()`.

### 14.10 `search.py`

**File:** `homestack/commands/search.py` (47 lines)

**Command:** `homestack search [query]`

If `query` is provided, calls `registry_search(query)`. Otherwise calls `registry_list()` to show all available apps.

Prints a table with: NAME, CATEGORY, PORT, DESCRIPTION. Apps that are already installed get a green ✓ marker.

### 14.11 `catalog.py`

**File:** `homestack/commands/catalog.py` (57 lines)

**Command:** `homestack catalog [update|list]`

This is a Click **group** (not a simple command), with two subcommands:

- `homestack catalog update` → calls `registry_sync()` to pull latest catalog
- `homestack catalog list` → displays all catalog apps in a table

If invoked without a subcommand (`homestack catalog`), defaults to `update`.

### 14.12 `logs.py`

**File:** `homestack/commands/logs.py` (36 lines)

**Command:** `homestack logs <app_name> [-f/--follow] [-n/--tail N]`

**Options:**
- `-f/--follow`: Stream logs in real-time (like `docker compose logs -f`)
- `-n/--tail N`: Number of lines to show (default: 100)

Passes through to `compose_cmd(install_dir, "logs", "--tail", str(tail), ["--follow"])`.

Handles `KeyboardInterrupt` gracefully for follow mode (user presses Ctrl+C to stop).

### 14.13 `exec.py`

**File:** `homestack/commands/exec.py` (50 lines)

**Command:** `homestack exec <app_name> [-s/--service SERVICE] <command...>`

Runs an arbitrary command inside a container.

**Service detection:** If `--service` is not specified, reads compose.yaml and uses the first service name.

**Click configuration:** Uses `context_settings={"ignore_unknown_options": True}` so that unknown flags (e.g., `homestack exec myapp ls -la`) are passed through to the container command instead of being parsed by Click.

**Exit code pass-through:** `sys.exit(result.returncode)` — the CLI exits with whatever code the container command returned.

### 14.14 `doctor.py`

**File:** `homestack/commands/doctor.py` (108 lines)

**Command:** `homestack doctor`

Runs 10 system health checks and prints results with ✓/✗ markers:

| # | Check | How |
|---|-------|-----|
| 1 | Docker installed | `shutil.which("docker")` |
| 2 | Docker daemon running | `docker info` exit code |
| 3 | Docker Compose v2 | `docker compose version` exit code |
| 4 | Git installed | `shutil.which("git")` |
| 5 | HomeStack directory | `HOMESTACK_DIR.is_dir()` |
| 6 | Config file exists | `CONFIG_FILE.is_file()` |
| 7 | Database accessible | `DB_FILE.is_file()` |
| 8 | Database schema OK | `db_init()` succeeds |
| 9 | WAL file size | Warns if `-wal` file > 10 MB |
| 10 | Disk space | `os.statvfs()` — warns if < 1 GB free |

After checks, lists all installed apps.

**`_check(label: str, ok: bool) → bool`** (private helper)

Prints a single check line with green ✓ or red ✗. Returns the `ok` value for chaining.

---

## 15. Global Config

**File:** `config/homestack.env`

A simple `KEY=VALUE` file loaded as the first `--env-file` in every `compose_cmd()` call.

**Keys:**

| Key | Purpose | Example |
|-----|---------|---------|
| `HOMESTACK_DIR` | Installation directory | `/homestack` |
| `APPDATA` | Container data directory | `/homestack/AppData` |
| `BACKUPS` | Backup storage | `/homestack/Backups` |
| `MEDIA` | Shared media library | `/homestack/Media` |
| `TZ` | Timezone | `Europe/Bratislava` |
| `PUID` | User ID for containers | `1000` |
| `PGID` | Group ID for containers | `1000` |
| `DOCKER_USER` | `PUID:PGID` combined | `1000:1000` |
| `HOMESTACK_APPS_REPO` | Catalog Git URL | `https://github.com/filippvizvary/homestack-apps.git` |

These variables are available in every compose.yaml via `${APPDATA}`, `${MEDIA}`, `${TZ}`, etc.

---

## 16. Build Configuration

**File:** `pyproject.toml` (31 lines)

```toml
[build-system]
requires = ["setuptools>=64", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "homestack"
version = "0.3.0"
description = "Self-hosted Docker management CLI"
requires-python = ">=3.9"
dependencies = [
    "click>=8.0",
    "pyyaml>=6.0",
]

[project.scripts]
homestack = "homestack.cli:cli"

[project.optional-dependencies]
dev = ["pytest>=7.0"]
```

**Key points:**
- `[project.scripts]` creates a `homestack` console entry point when pip-installed
- Only two runtime dependencies: Click and PyYAML
- pytest is a dev-only dependency
- `setuptools.packages.find` with `include = ["homestack*"]` ensures only the package is included

---

## 17. Setup Script

**File:** `setup.sh` (~370 lines)

Interactive first-run installer. Only used once to bootstrap a new HomeStack installation.

**What it does:**
1. Checks for root/sudo
2. Installs system packages: `git`, `curl`
3. Installs Docker + Docker Compose plugin
4. Creates `homestack` system user and group
5. Creates Python 3 venv at `.venv/`
6. Runs `pip install -e .` inside the venv
7. Interactively configures paths and timezone
8. Writes `config/homestack.env`
9. Initializes the database
10. Syncs the catalog
11. Sets file permissions
12. Creates symlink for `homestack` to `/usr/local/bin/`

---

## 18. Environment Variable Stacking

This is one of the most important cross-cutting concepts in HomeStack — understanding it helps you make sense of how `compose_cmd()` works and why there are three separate env files. When `compose_cmd()` runs Docker Compose, it passes up to three `--env-file` flags. Docker Compose processes them in order, with later files overriding earlier ones.

```
Layer 1: config/homestack.env      ← APPDATA, MEDIA, TZ, PUID, PGID, DOCKER_USER
Layer 2: installed/<app>/config.env ← APP_IMAGE, APP_PORT, etc.
Layer 3: installed/<app>/secrets.env ← DB_PASSWORD, API_KEY, etc.
```

**Example of how this works in practice:**

`homestack.env` defines:
```env
APPDATA=/homestack/AppData
TZ=America/New_York
PUID=1000
```

`installed/jellyfin/config.env` defines:
```env
JELLYFIN_SERVER=jellyfin/jellyfin:10.11.5
```

`installed/jellyfin/secrets.env` is empty (Jellyfin has no secrets).

The compose.yaml for Jellyfin uses:
```yaml
services:
  jellyfin:
    image: ${JELLYFIN_SERVER}
    volumes:
      - ${APPDATA}/jellyfin/config:/config
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
```

Docker Compose resolves all `${VAR}` references from the stacked env files.

---

## 19. Locking and Concurrency

HomeStack uses file-based locking via `fcntl.flock()` to prevent concurrent modifications. You've already seen the lock functions in [section 8.3](#83-file-locking) — this section explains the overall strategy.

**When locks are acquired:**
- All mutating commands (install, update, remove, backup, restore, start, stop, restart)

**When locks are NOT acquired:**
- Read-only commands (status, list, search, catalog, logs, exec, doctor, log)

**Lock behavior:**
- Non-blocking (`LOCK_NB`) — if another process holds the lock, immediately exit with error
- User gets message: "Another homestack process is running. If this is wrong, remove .lock"
- Lock file is `.lock` in `HOMESTACK_DIR`

**SQLite concurrency:**
- WAL mode provides concurrent reads with one writer
- Each function opens its own short-lived connection
- No long-lived transactions

---

## 20. Error Handling Patterns

### Pattern 1: `core.error()` + `sys.exit(1)`

Used for unrecoverable user errors:
```python
if not core.is_installed(app_name):
    core.error(f"'{app_name}' is not installed.")
    sys.exit(1)
```

### Pattern 2: `raise SystemExit(1)`

Click-friendly variant (same behavior as `sys.exit(1)`):
```python
if not core.is_installed(app_name):
    core.error(f"'{app_name}' is not installed.")
    raise SystemExit(1)
```

### Pattern 3: Rollback on exception

Used in install.py — wraps the entire install in try/except:
```python
try:
    # ... install steps ...
except Exception:
    core.warn("Installation failed, rolling back...")
    compose_cmd(install_dir, "down", check=False)
    shutil.rmtree(install_dir, ignore_errors=True)
    db.db_remove_app(install_app)
    sys.exit(1)
```

### Pattern 4: Silent audit logging

`db_log_action()` is wrapped in try/except that passes silently. Logging failures must never crash the CLI.

### Pattern 5: Docker fallback for permissions

When `shutil.rmtree()` fails with `PermissionError` on container-owned files:
```python
try:
    shutil.rmtree(target)
except PermissionError:
    subprocess.run(["docker", "run", "--rm", "-v", f"{target}:/cleanup",
                     "busybox", "rm", "-rf", "/cleanup"])
```

### Pattern 6: `check=False` + `quiet_err=True`

For Docker commands that can legitimately fail (e.g., `docker compose down` when already stopped):
```python
core.compose_cmd(install_dir, "down", check=False, quiet_err=True)
```

---

## 21. Test Suite

72 tests in 5 test files, using pytest. All tests use temporary directories and mock databases — no Docker or network access required for unit tests.

### 21.1 `conftest.py` — Fixtures

**File:** `tests/conftest.py` (174 lines)

#### Path Constants

```python
TESTS_DIR = Path(__file__).parent
PROJECT_DIR = TESTS_DIR.parent
FIXTURES_DIR = TESTS_DIR / "fixtures"
```

#### `tmp_homestack` fixture

**Scope:** Per-test (default pytest function scope)

Creates a complete temporary HomeStack environment:

```
tmp_path/homestack/
├── installed/
├── AppData/
├── Backups/
├── Media/
├── config/
│   └── homestack.env    ← fully populated
└── .cache/homestack-apps/apps/
```

**Critical step:** Calls `monkeypatch.setenv("HOMESTACK_DIR", str(hs))` and then `core.refresh_paths()`. This redirects ALL module-level path constants to the temporary directory, ensuring tests never touch the real filesystem.

The homestack.env in the test environment contains all required keys (HOMESTACK_DIR, APPDATA, BACKUPS, MEDIA, TZ, PUID, PGID, DOCKER_USER, HOMESTACK_APPS_REPO) pointing to the temp directory.

#### `db_init` fixture

**Depends on:** `tmp_homestack`

Calls `db.db_init()` to create the SQLite schema in the temporary database. Returns the `tmp_homestack` path.

#### `fixture_catalog` fixture

**Depends on:** `tmp_homestack`

Copies the test fixture catalog (from `tests/fixtures/catalog/apps/`) into the temporary environment's `.cache/homestack-apps/apps/` directory. Returns the destination path.

#### `create_fixture_app(apps_dir, name, ...)` (function, not fixture)

Creates a complete mock app definition in a given directory. Parameters:
- `name`: App name
- `port`: Port number (default 18080)
- `priority`: Priority value (default 50)
- `secrets`: Raw YAML string for secrets block
- `networks`: YAML list string (default `"[]"`)
- `appdata_dirs`: YAML list string (default `"[<name>]"`)
- `media_dirs`: YAML list string (default `"[]"`)

Creates three files:
- `app.yaml` with all metadata fields
- `compose.yaml` with a minimal nginx service
- `config.env` with `APPNAME_SERVER=nginx:1.27-alpine`

#### `mock_install_app(tmp_homestack, name, version, apps_dir)` (function, not fixture)

Simulates an app installation without Docker:
1. Creates `installed/<name>/` directory
2. Copies files from fixture catalog to installed directory
3. Creates empty `secrets.env` with 0600 permissions
4. Creates `AppData/<name>/` directory
5. Adds DB record via `db_set_installed()`

This is used in tests that need an "installed" app without running Docker.

### 21.2 `test_core.py`

**File:** `tests/unit/test_core.py` (68 lines)

5 test classes, 10 tests total:

**`TestPaths`** (3 tests)
- `test_homestack_dir_from_env`: Verifies `HOMESTACK_DIR` matches tmp_homestack path
- `test_installed_dir`: Verifies `INSTALLED_DIR` is `<root>/installed`
- `test_db_file`: Verifies `DB_FILE` is `<root>/homestack.db`

**`TestValidatePathComponent`** (5 tests)
- `test_valid`: "myapp" passes
- `test_rejects_empty`: "" fails
- `test_rejects_slash`: "a/b" fails
- `test_rejects_dotdot`: ".." fails
- `test_rejects_embedded_dotdot`: "foo/../bar" fails

**`TestCheckPort`** (1 test)
- `test_available_port`: Port 59999 should be available

**`TestLocking`** (2 tests)
- `test_acquire_release`: acquire then release succeeds
- `test_context_manager`: `with homestack_lock():` works

**`TestIsInstalled`** (2 tests)
- `test_not_installed`: "nonexistent" returns False
- `test_installed`: Creating the directory + app.yaml makes it True

**`TestEnsureDir`** (1 test)
- `test_creates_directory`: Nested directory is created

### 21.3 `test_db.py`

**File:** `tests/unit/test_db.py` (137 lines)

7 test classes, 18 tests total:

**`TestDbInit`** (2 tests)
- `test_creates_all_tables`: Verifies all 5 tables exist in SQLite
- `test_idempotent`: Calling `db_init()` twice doesn't crash

**`TestAppLifecycle`** (7 tests)
- Version set/get, is_installed, install_date, catalog_version, update_version, remove (with cascade)

**`TestConfigOverrides`** (3 tests)
- `test_track_defaults`: Tracks defaults with is_modified=False
- `test_mark_modified`: After marking, is_modified returns True
- `test_insert_or_ignore_preserves_modified`: **Bug fix test** — ensures re-tracking doesn't reset user modifications

**`TestBackups`** (2 tests)
- Record and list, remove by ID

**`TestHealth`** (1 test)
- Update and get health status

**`TestAuditLog`** (2 tests)
- Log and retrieve, never crashes on unusual characters

### 21.4 `test_yaml_parser.py`

**File:** `tests/unit/test_yaml_parser.py` (109 lines)

5 test classes, 20 tests total:

**`TestYamlGet`** (7 tests)
- Scalar strings, display names with spaces, integers as strings, URL values, missing keys, backup_strategy

**`TestYamlGetArray`** (5 tests)
- Inline arrays, empty arrays, missing keys

**`TestParseSecrets`** (7 tests)
- Three secrets parsed, key names, generate flag, length, default values, no-secrets case

**`TestLoadYaml`** (2 tests)
- Returns dict, missing file returns empty dict

### 21.5 `test_secrets.py`

**File:** `tests/unit/test_secrets.py` (106 lines)

3 test classes, 12 tests total:

**`TestGeneratePassword`** (4 tests)
- Default length (32), custom length (16), alphanumeric only, uniqueness

**`TestGenerateSecretsFile`** (6 tests)
- Creates file, correct permissions (0600), contains all keys, default values used, generated password lengths, no-secrets creates empty file

**`TestAppendNewSecrets`** (2 tests)
- Adds missing keys, doesn't overwrite existing keys

### 21.6 `test_registry.py`

**File:** `tests/unit/test_registry.py` (72 lines)

3 test classes, 6 tests total:

**`TestRegistryFind`** (3 tests)
- Finds existing app, missing app returns empty, case-insensitive fallback

**`TestRegistryList`** (2 tests)
- Lists multiple apps, empty catalog

**`TestRegistrySearch`** (2 tests)
- Search by name substring, no results for gibberish

### 21.7 Test Fixtures (YAML files)

**`tests/fixtures/sample.yaml`** — Full-featured app definition:
- 3 secrets (generated password, default value, generated API key)
- Networks, appdata_dirs, media_dirs all populated
- backup_strategy: stop

**`tests/fixtures/nosecrets.yaml`** — Minimal app definition:
- No secrets, no networks, no media_dirs
- Used to test empty/missing field handling

**`tests/fixtures/catalog/apps/testapp/`** — Mock catalog app:
- Complete 4-file app definition
- Used by `fixture_catalog` fixture

---

## 22. End-to-End Data Flows

### Install Flow

```
homestack install jellyfin
│
├── cli.py: db_init(), dispatch to install.py
│
├── install.py: cmd_install("jellyfin")
│   ├── core.homestack_lock()           → acquire flock
│   ├── registry.registry_find()        → .cache/homestack-apps/apps/jellyfin/
│   │   └── registry.registry_ensure()  → git clone if missing
│   ├── yaml_parser.yaml_get()          → read name, port, version from app.yaml
│   ├── yaml_parser.yaml_get_array()    → read depends_on, networks, appdata_dirs, media_dirs
│   ├── core.check_port_available(8096) → True
│   ├── shutil.copy2()                  → compose.yaml, app.yaml, config.env, test.yaml → installed/jellyfin/
│   ├── core.ensure_network()           → docker network create (if needed)
│   ├── core.ensure_dir()               → AppData/jellyfin/, Media/* directories
│   ├── _precreate_volumes()            → parse compose.yaml, mkdir volume paths
│   ├── secrets.generate_secrets_file() → installed/jellyfin/secrets.env (chmod 600)
│   ├── db.db_track_config_defaults()   → store config.env defaults in DB
│   ├── core.compose_cmd("up", "-d")    → docker compose up -d
│   │   └── --env-file homestack.env --env-file config.env --env-file secrets.env
│   ├── health.run_health_checks()      → HTTP checks + exec checks
│   ├── db.db_set_installed()           → INSERT into apps table
│   └── db.db_log_action("install")     → INSERT into audit_log
│
└── release lock
```

### Update Flow

```
homestack update jellyfin
│
├── _update_app("jellyfin")
│   ├── registry.registry_find()            → find in catalog
│   ├── compare: installed_ver != catalog_ver
│   ├── AUTO BACKUP:
│   │   ├── tarfile.open()                  → backup installed/jellyfin/ config
│   │   └── db.db_record_backup()           → record in DB
│   ├── shutil.copy2()                      → new app.yaml, compose.yaml, test.yaml
│   ├── _merge_config():
│   │   ├── read current config.env
│   │   ├── copy new config.env as base
│   │   ├── for each key: db.db_is_config_modified()
│   │   │   ├── if modified → preserve user value
│   │   │   └── if default → use new catalog value
│   │   └── rename merged → config.env
│   ├── secrets.append_new_secrets()        → add new secret keys only
│   ├── db.db_set_updated()                 → update version in DB
│   ├── db.db_track_config_defaults()       → re-track from new config
│   ├── core.compose_cmd("pull")            → pull new images
│   ├── core.compose_cmd("up", "-d")        → recreate containers
│   ├── health.run_health_checks()          → verify app is working
│   └── db.db_log_action("update")
```

### Backup/Restore Flow

```
homestack backup jellyfin
│
├── Read backup_strategy: "live"
├── Create config tar: Backups/jellyfin/jellyfin_config_20250101_120000.tar.gz
├── Create data tar:   Backups/jellyfin/jellyfin_data_20250101_120000.tar.gz
├── db.db_record_backup() × 2
├── _rotate_backups() → keep last 5
└── db.db_log_action("backup")

homestack restore jellyfin
│
├── db.db_list_backups() → list available
├── User selects backup #
├── VERIFY: tarfile.open() → tar.getmembers()    ← integrity check BEFORE stopping
├── compose_cmd("down")                           ← stop only after verified
├── tarfile.extractall() → restore data
├── compose_cmd("up", "-d")                       ← restart
└── db.db_log_action("restore")
```

---

## 23. Adding a New Command

Step-by-step guide for adding a new CLI command:

### Step 1: Create the command file

Create `homestack/commands/<verb>.py`:

```python
"""homestack <verb> <args>"""
from __future__ import annotations
import click
from homestack import core, db

@click.command("<verb>")
@click.argument("app_name")
def cmd_<verb>(app_name: str) -> None:
    """One-line description shown in --help."""
    
    # Validate input
    if not core.is_installed(app_name):
        core.error(f"'{app_name}' is not installed.")
        raise SystemExit(1)
    
    # Acquire lock if this is a mutating operation
    with core.homestack_lock():
        # Do work
        core.step("Doing something")
        # ...
        core.success("Done")
        db.db_log_action("<verb>", app_name, "Details")
```

### Step 2: Register in cli.py

Add two lines to `homestack/cli.py`:

```python
from homestack.commands.<verb> import cmd_<verb>
cli.add_command(cmd_<verb>)
```

### Step 3: Write tests

Create `tests/unit/test_<verb>.py` with pytest tests.

### Step 4: Decide on locking

- **Mutating** (changes files, DB, or Docker state): Use `core.homestack_lock()`
- **Read-only** (queries, displays): No lock needed

---

## 24. Adding a New Database Table

### Step 1: Add CREATE TABLE to schema

In `homestack/db.py`, add to the `_SCHEMA` string:

```sql
CREATE TABLE IF NOT EXISTS my_table (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    app   TEXT NOT NULL,
    ...
);
```

Since `db_init()` uses `CREATE TABLE IF NOT EXISTS`, this is safe to deploy — existing databases get the new table, new databases get it too.

### Step 2: Add CRUD functions

Follow the naming convention `db_<action>_<noun>()`:

```python
def db_set_my_thing(app: str, value: str) -> None:
    with _connect() as conn:
        conn.execute("INSERT OR REPLACE INTO my_table (...) VALUES (?)", (...))

def db_get_my_thing(app: str) -> str:
    with _connect() as conn:
        row = conn.execute("SELECT ... FROM my_table WHERE app = ?", (app,)).fetchone()
    return row[0] if row else ""
```

### Step 3: Clean up on app removal

If the table stores per-app data, add a DELETE to `db_remove_app()`:

```python
def db_remove_app(app: str) -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM apps WHERE name = ?", (app,))
        conn.execute("DELETE FROM config_overrides WHERE app = ?", (app,))
        conn.execute("DELETE FROM health WHERE app = ?", (app,))
        conn.execute("DELETE FROM my_table WHERE app = ?", (app,))  # ← add this
```

### Step 4: Write tests

Test in `tests/unit/test_db.py` with the existing `db_init` fixture.

---

## Appendix: Quick Reference

### All functions by module

**core.py (14 functions):**
`_resolve_homestack_dir`, `refresh_paths`, `step`, `success`, `warn`, `error`, `acquire_lock`, `release_lock`, `validate_path_component`, `check_port_available`, `compose_cmd`, `get_installed_apps`, `is_installed`, `ensure_network`, `ensure_dir` + 1 class (`homestack_lock`)

**db.py (20 functions):**
`_connect`, `_now`, `db_init`, `db_set_installed`, `db_set_catalog_version`, `db_set_updated`, `db_remove_app`, `db_get_installed_version`, `db_get_catalog_version`, `db_is_installed`, `db_get_install_date`, `db_track_config_defaults`, `db_update_config_default`, `db_is_config_modified`, `db_mark_config_modified`, `db_get_modified_configs`, `db_record_backup`, `db_list_backups`, `db_list_all_backups`, `db_remove_backup`, `db_update_health`, `db_get_health`, `db_log_action`, `db_get_audit_log`

**registry.py (7 functions):**
`_repo_url`, `registry_sync`, `_update_catalog_versions`, `registry_ensure`, `registry_list`, `registry_find`, `registry_search`

**secrets.py (3 functions):**
`generate_password`, `generate_secrets_file`, `append_new_secrets`

**yaml_parser.py (6 functions + 3 dataclasses):**
`load_yaml`, `yaml_get`, `yaml_get_array`, `parse_secrets`, `parse_health_checks`, `parse_exec_checks`, `get_startup_time` + `SecretDef`, `HealthCheck`, `ExecCheck`

**health.py (4 functions):**
`run_health_checks`, `_wait_for_healthy`, `_run_http_check`, `_run_exec_check`

### Import dependency graph

```
cli.py
  ├── db.py ← core.py
  └── commands/*.py
        ├── core.py
        ├── db.py ← core.py
        ├── registry.py ← core.py, yaml_parser.py
        ├── secrets.py ← yaml_parser.py
        ├── health.py ← core.py, yaml_parser.py
        └── yaml_parser.py (no homestack imports)
```

`yaml_parser.py` is the only module with no internal dependencies — it only uses PyYAML and standard library.
