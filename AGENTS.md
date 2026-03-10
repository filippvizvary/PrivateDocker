# AGENTS.md — HomeStack CLI

> Comprehensive context file for AI coding agents working on this repository.

## Project Overview

**HomeStack** is a Python CLI tool that manages self-hosted Docker Compose applications on a single Linux server. It provides install, update, backup, restore, and lifecycle management with SQLite-backed state tracking.

- **Language:** Python 3.9+ (Click CLI framework)
- **Version:** 0.3.0
- **License:** MIT
- **Owner:** filippvizvary (GitHub)
- **Build system:** `setuptools` via `pyproject.toml`
- **Dependencies:** `click>=8.0`, `pyyaml>=6.0`
- **System dependencies:** `git`, `docker` (with Compose v2 plugin), `tar`
- **Companion repo:** `homestack-apps` — community catalog of app definitions

## Architecture

```
User → homestack CLI (Click entrypoint)
         ├── homestack/core.py       (paths, compose_cmd, locking, helpers)
         ├── homestack/db.py         (SQLite abstraction layer)
         ├── homestack/registry.py   (catalog sync via git)
         ├── homestack/secrets.py    (secret generation)
         ├── homestack/yaml_parser.py (YAML parser with dataclasses)
         ├── homestack/health.py     (post-install health checks)
         └── homestack/commands/     (one file per CLI command)
              ├── install.py
              ├── update.py
              ├── remove.py
              ├── backup.py
              ├── restore.py
              ├── start.py
              ├── stop.py
              ├── restart.py
              ├── status.py
              ├── list.py
              ├── search.py
              ├── catalog.py
              ├── logs.py
              ├── exec.py
              └── doctor.py
```

### Data Flow

```
homestack-apps repo (GitHub)
    ↓ git clone/pull
.cache/homestack-apps/apps/<app>/
    ├── app.yaml       (manifest: ports, secrets, networks, priority)
    ├── compose.yaml   (Docker Compose definition)
    ├── config.env     (default image tags + config)
    └── test.yaml      (health check definitions)
    ↓ homestack install <app>
installed/<app>/
    ├── compose.yaml   (copied from catalog)
    ├── config.env     (copied, user may edit)
    └── secrets.env    (auto-generated, chmod 600)
    ↓ docker compose
Running containers
```

### Environment Variable Stacking Order

When `compose_cmd()` runs Docker Compose, env files are loaded in this order (last wins):

1. `config/homestack.env` — global defaults (APPDATA, MEDIA, TZ, PUID, PGID, etc.)
2. `installed/<app>/config.env` — app-specific config (image tags, ports)
3. `installed/<app>/secrets.env` — generated secrets (DB passwords, etc.)

This is implemented via `--env-file` flags passed to `docker compose`.

## Directory Structure

```
homestack/
├── bin/homestack           # Shell wrapper (activates venv, delegates to Python)
├── homestack/              # Python package
│   ├── __init__.py         # __version__ = "0.3.0"
│   ├── __main__.py         # python -m homestack support
│   ├── cli.py              # Click group, command registration, db_init
│   ├── core.py             # Paths, compose_cmd, locking, helpers
│   ├── db.py               # SQLite abstraction layer (5 tables)
│   ├── registry.py         # Git-based catalog sync
│   ├── secrets.py          # Password generation + secrets.env management
│   ├── yaml_parser.py      # PyYAML-based parser with typed dataclasses
│   ├── health.py           # Post-install health check runner
│   └── commands/           # One file per command, each exports a Click command
│       ├── __init__.py
│       ├── install.py
│       ├── update.py
│       ├── remove.py
│       ├── backup.py
│       ├── restore.py
│       ├── start.py
│       ├── stop.py
│       ├── restart.py
│       ├── status.py
│       ├── list.py
│       ├── search.py
│       ├── catalog.py
│       ├── logs.py
│       ├── exec.py
│       └── doctor.py
├── config/
│   └── homestack.env       # Global config (paths, timezone, UID/GID)
├── setup.sh                # Installer (interactive + NONINTERACTIVE mode)
├── setup-minimal-debian.sh # Root-first bootstrap for minimal Debian hosts
├── deploy/
│   └── unattended-debian/  # preseed + first-boot automation bundle
├── pyproject.toml          # Build config, dependencies, entry points
├── installed/              # Per-app runtime directories (created by install)
│   └── <app>/
│       ├── compose.yaml
│       ├── config.env
│       └── secrets.env     # chmod 600, .gitignored
├── AppData/                # Persistent container data (bind mounts)
├── Backups/                # Tar archives (config + data)
├── Media/                  # Shared media library
├── .cache/
│   └── homestack-apps/     # Cloned catalog repo
├── .venv/                  # Python virtual environment
├── homestack.db            # SQLite database
├── .lock                   # flock file for concurrency control
└── tests/                  # pytest test suite
    ├── conftest.py         # Shared fixtures (tmp_homestack, etc.)
    └── unit/
        ├── test_core.py
        ├── test_db.py
        ├── test_yaml_parser.py
        ├── test_secrets.py
        └── test_registry.py
```

## File-by-File Reference

### bin/homestack (~15 lines)

Shell wrapper script. Activates the Python venv and delegates to the `homestack` entry point.

**Key behaviors:**
- Resolves `HOMESTACK_DIR` from the script's location
- Activates `.venv/bin/activate`
- Passes all arguments through to the `homestack` Python command

### homestack/cli.py (~100 lines)

Click CLI entry point. Defines the main command group and registers all subcommands.

**Functions:**

| Function | Purpose |
|----------|---------|
| `cli()` | `@click.group` — main entry point; calls `db_init()` on every invocation |
| `cmd_log(limit)` | `@cli.command("log")` — displays audit log entries with color coding |

Registers 16 subcommands via `cli.add_command()`.

**Command dispatch table:**

| Command | File | Lock Required |
|---------|------|---------------|
| `install` | `commands/install.py` | Yes |
| `update` | `commands/update.py` | Yes |
| `remove` | `commands/remove.py` | Yes |
| `backup` | `commands/backup.py` | Yes |
| `restore` | `commands/restore.py` | Yes |
| `start` | `commands/start.py` | Yes |
| `stop` | `commands/stop.py` | Yes |
| `restart` | `commands/restart.py` | Yes |
| `config` | `commands/config.py` | Partial (edit/reset only) |
| `status` | `commands/status.py` | No |
| `list` | `commands/list.py` | No |
| `search` | `commands/search.py` | No |
| `catalog` | `commands/catalog.py` | No |
| `logs` | `commands/logs.py` | No |
| `exec` | `commands/exec.py` | No |
| `doctor` | `commands/doctor.py` | No |
| `log` | inline in `cli.py` | No |

### homestack/core.py (~196 lines)

Shared utilities imported by all commands.

**Module-level constants (dynamically resolved):**
- `HOMESTACK_DIR` — repo root
- `INSTALLED_DIR` — `$HOMESTACK_DIR/installed`
- `CONFIG_DIR` / `CONFIG_FILE` — `config/homestack.env`
- `APPDATA_DIR`, `BACKUPS_DIR`, `MEDIA_DIR`
- `DB_FILE` — `homestack.db`
- `LOCK_FILE` — `.lock`
- `CACHE_DIR` / `APPS_DIR` — `.cache/homestack-apps/apps`

**Functions:**

| Function | Purpose |
|----------|---------|
| `_resolve_homestack_dir()` | Resolves base dir from `HOMESTACK_DIR` env var or script location |
| `refresh_paths()` | Re-derives all path globals (used by test fixtures) |
| `step(msg)` / `success(msg)` / `warn(msg)` / `error(msg)` | Colored output helpers |
| `acquire_lock()` | Non-blocking `flock`; exits with error if lock held |
| `release_lock()` | Releases the flock |
| `homestack_lock` | Context manager wrapping lock acquire/release |
| `validate_path_component(name)` | Rejects empty strings, `/`, or `..` — prevents path traversal |
| `check_port_available(port)` | Uses `socket.connect_ex()` to check if a TCP port is free |
| `compose_cmd(app_dir, *args, capture=False, check=True)` | Runs `docker compose` with stacked `--env-file` flags. Central function for ALL Docker operations. |
| `get_installed_apps()` | Lists installed apps sorted by priority (reads app.yaml) |
| `is_installed(app_name)` | Checks if app dir + app.yaml exist in installed/ |
| `ensure_network(name)` | Creates Docker network if it doesn't exist |
| `ensure_dir(path)` | `mkdir -p` equivalent |

### homestack/db.py (~224 lines)

Full SQLite abstraction layer. All queries go through `sqlite3`.

**Functions:**

| Function | Purpose |
|----------|---------|
| `_connect()` | Opens SQLite connection with WAL mode and Row factory |
| `_now()` | Returns UTC ISO 8601 timestamp |
| `db_init()` | Creates all 5 tables with `CREATE TABLE IF NOT EXISTS` |
| `db_set_installed(app, version)` | INSERT/REPLACE into `apps` table |
| `db_set_catalog_version(app, version)` | UPDATE `catalog_version` for an app |
| `db_set_updated(app, version)` | UPDATE `installed_version` and `updated_at` |
| `db_remove_app(app)` | DELETE from `apps`, `config_overrides`, `health` |
| `db_get_installed_version(app)` | SELECT installed_version |
| `db_get_catalog_version(app)` | SELECT catalog_version |
| `db_is_installed(app)` | Returns True if app exists in DB |
| `db_get_install_date(app)` | Returns installed_at timestamp |
| `db_track_config_defaults(app, config_file)` | Stores all config.env defaults (INSERT OR IGNORE) |
| `db_update_config_default(app, key, value)` | Updates default only if user hasn't modified |
| `db_is_config_modified(app, key, current_value)` | Returns True if user changed from default |
| `db_mark_config_modified(app, key, value)` | Marks config key as user-modified |
| `db_get_modified_configs(app)` | Returns user-modified key/value pairs |
| `db_record_backup(app, path, size, type)` | INSERT into `backups` |
| `db_list_backups(app)` / `db_list_all_backups()` | SELECT backups newest first |
| `db_remove_backup(backup_id)` | DELETE backup by id |
| `db_update_health(app, container, status)` | INSERT OR REPLACE health status |
| `db_get_health(app)` | Returns health records |
| `db_log_action(action, app, detail, exit_code)` | INSERT audit log (wrapped in try/except — never crashes) |
| `db_get_audit_log(limit)` | Returns latest audit log entries |

**Database Schema (SQLite):**

```sql
CREATE TABLE apps (
    name            TEXT PRIMARY KEY,
    installed_version TEXT,
    catalog_version TEXT,
    installed_at    TEXT,
    updated_at      TEXT,
    status          TEXT
);

CREATE TABLE config_overrides (
    app             TEXT,
    key             TEXT,
    value           TEXT,
    is_user_modified INTEGER DEFAULT 0,
    PRIMARY KEY (app, key)
);

CREATE TABLE backups (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    app             TEXT,
    path            TEXT,
    size_bytes      INTEGER,
    created_at      TEXT,
    type            TEXT
);

CREATE TABLE health (
    app             TEXT,
    container       TEXT,
    status          TEXT,
    checked_at      TEXT,
    PRIMARY KEY (app, container)
);

CREATE TABLE audit_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       TEXT,
    action          TEXT,
    app             TEXT,
    detail          TEXT,
    exit_code       INTEGER
);
```

### homestack/registry.py (~149 lines)

Manages the local clone of the `homestack-apps` catalog.

**Functions:**

| Function | Purpose |
|----------|---------|
| `_repo_url()` | Resolves catalog repo URL from env/config/default |
| `registry_sync()` | Clones or pulls the catalog repo; updates catalog versions in DB |
| `_update_catalog_versions()` | Syncs catalog version numbers into DB for installed apps |
| `registry_ensure()` | Ensures catalog is available locally; syncs if missing |
| `registry_list()` | Returns list of all catalog apps as dicts |
| `registry_find(app_name)` | Finds app dir by name (exact + case-insensitive fallback) |
| `registry_search(query)` | Substring search across name/display_name/description/category |

### homestack/secrets.py (~125 lines)

Generates and manages `secrets.env` files.

**Functions:**

| Function | Purpose |
|----------|---------|
| `generate_password(length)` | Generates alphanumeric password via `secrets.choice()` |
| `generate_secrets_file(app_yaml, output, *, interactive=True)` | Creates `secrets.env` from app.yaml; auto-generates, prompts (if interactive), or uses defaults |
| `append_new_secrets(app_yaml, secrets_file, *, interactive=True)` | During updates: adds new secret keys without overwriting existing ones |

### homestack/yaml_parser.py (~131 lines)

Full YAML parser using PyYAML with typed dataclasses.

**Dataclasses:**

| Class | Fields |
|-------|--------|
| `SecretDef` | `key`, `prompt`, `default`, `generate`, `length` |
| `HealthCheck` | `url`, `method`, `expected_status`, `body_contains`, `timeout` |
| `ExecCheck` | `container`, `command`, `expected_output` |

**Functions:**

| Function | Purpose |
|----------|---------|
| `load_yaml(filepath)` | Loads YAML file via `yaml.safe_load`, returns dict |
| `yaml_get(filepath, key)` | Gets a scalar value as string |
| `yaml_get_array(filepath, key)` | Gets a list value as list of strings |
| `parse_secrets(filepath)` | Parses `secrets:` block into `list[SecretDef]` |
| `parse_health_checks(filepath)` | Parses `health_checks:` into `list[HealthCheck]` |
| `parse_exec_checks(filepath)` | Parses `exec_checks:` into `list[ExecCheck]` |
| `get_startup_time(filepath)` | Returns `startup_time` int (default 30) |

### homestack/health.py (~137 lines)

Post-install health check runner.

**Functions:**

| Function | Purpose |
|----------|---------|
| `run_health_checks(app_name, install_dir)` | Orchestrates all checks: waits for startup, runs HTTP + exec checks |
| `_wait_for_healthy(install_dir, timeout)` | Polls `docker compose ps` until containers report "Up" |
| `_run_http_check(app_name, hc, retries=5, retry_delay=3)` | HTTP check with retry logic for timing issues |
| `_run_exec_check(app_name, install_dir, ec)` | Runs `docker compose exec` and validates output |

### homestack/commands/ — Command Files

Every command file exports a Click command object.

#### install.py (~173 lines)
1. Takes app name argument + `--skip-checks` + `--defaults` flags
2. Detects interactive mode via `os.isatty(sys.stdin.fileno())`
3. Calls `registry_ensure` then `registry_find` to locate the app
4. Checks if already installed
5. Reads `app.yaml` for port, networks, appdata_dirs, media_dirs
6. Checks port availability
7. Creates Docker networks, appdata, and media directories
8. Copies `compose.yaml` and `config.env` to `installed/<app>/`
9. Pre-creates volume mount directories (`_precreate_volumes`)
10. Generates `secrets.env` via `generate_secrets_file`
11. Saves config defaults to DB
12. Starts the app via `compose_cmd up -d`
13. Runs health checks (unless `--skip-checks`)
14. Records in DB and audit log
15. **Rollback:** On failure, cleans up installed dir, networks, and DB entry

#### update.py (~139 lines)
1. Creates automatic backup before updating
2. Syncs catalog
3. Compares installed version vs catalog version
4. `_merge_config()`: Preserves user-modified values, updates defaults, adds new keys
5. Updates compose.yaml and appends new secrets
6. Pulls new images and recreates containers
7. Updates DB version and audit log

#### remove.py (~93 lines)
1. Stops containers via `compose_cmd down`
2. Removes Docker networks if unused
3. Optionally deletes AppData (Docker fallback for container-owned files)
4. Removes `installed/<app>/` directory and DB records

#### backup.py (~151 lines)
1. Reads `backup_strategy` from `app.yaml` (stop or live)
2. Creates config + data tar archives
3. Docker fallback for permission errors on container-owned files
4. Rotation: keeps last 5 backups per type

#### restore.py (~152 lines)
1. Interactive backup selection
2. Type-aware extraction (config vs data)
3. Restarts containers after restore

#### start.py / stop.py / restart.py
- Priority-ordered start/stop/restart for one or all apps

#### config.py (~191 lines)
Command group with three subcommands for managing app configuration:

**`homestack config show <app>`**
- Displays current configuration from `config.env`
- Shows each key, value, and status (modified or default)
- Queries DB to identify user-modified keys vs catalog defaults
- Truncates long values to 35 chars for display

**`homestack config edit <app> <key> <value>`**
- Updates a key in `config.env` (requires lock)
- Marks the key as user-modified in the database
- Prompts to restart the app to apply changes
- Fails if key doesn't exist (lists available keys)

**`homestack config reset <app> <key>`**
- Resets a config key to its catalog default (requires lock)
- Retrieves default value from `config_overrides` table
- Updates `config.env` and clears `is_user_modified` flag
- Logs action to audit log

All subcommands verify app is installed before proceeding.

#### logs.py (~40 lines)
- Takes app name argument + `-f/--follow` flag + `-n/--tail` (default 100)
- Streams Docker Compose logs via `compose_cmd`
- Handles `KeyboardInterrupt` for `--follow` mode

#### exec.py (~50 lines)
- Runs commands inside app containers
- Auto-detects first service from compose.yaml if `-s/--service` not specified
- Uses `context_settings={"ignore_unknown_options": True}` for pass-through args
- Passes through container exit code via `sys.exit(result.returncode)`

#### doctor.py (~90 lines)
- System health check — no lock required
- 10 checks: Docker installed, Docker daemon running, Docker Compose v2, git, HomeStack dir, config file, database accessible, database schema, app catalog cached, disk space
- Lists all installed apps at the end
- Warns if available disk space < 1 GB

#### status.py / list.py / search.py / catalog.py
- Read-only commands, no lock required

### setup.sh (~460 lines)

First-run installer with interactive and unattended support:
1. Requires root and resolves installer defaults
2. Installs system dependencies (`git`, `curl`, `python3`, `sqlite3`)
3. Installs Docker + Compose plugin
4. Creates `homestack` system user and group
5. Adds service + CLI users to required groups
6. Handles existing install directories using policy (`fail|update|keep|reinstall`)
7. Writes or preserves `config/homestack.env`
8. Creates Python venv and installs HomeStack package
9. Initializes database and syncs catalog
10. Sets permissions and creates CLI symlink

**Unattended env contract (`NONINTERACTIVE=1`):**
- `HOMESTACK_SETUP_EXISTING` → `fail|update|keep|reinstall` (default: `fail`)
- `HOMESTACK_RECONFIGURE` → `0|1` (default: `0`)
- `HOMESTACK_REAL_USER` → target login user for group assignment
- `TZ`, `PUID`, `PGID`, `HOMESTACK_APPS_REPO`, `HOMESTACK_DIR`

### setup-minimal-debian.sh (~220 lines)

Root-first bootstrap for minimal Debian where `sudo` and full root PATH are missing:
1. Fixes PATH, installs base packages + `sudo`
2. Installs Docker CE and Compose plugin
3. Clones HomeStack and runs `setup.sh` as root
4. Supports noninteractive mode for existing-dir handling (`fail|reinstall`)
5. Passes unattended env vars through to `setup.sh`

### deploy/unattended-debian/

Bundle for fully unattended provisioning:
- `preseed.cfg` — Debian installer automation template
- `homestack-firstboot.service` — one-shot first-boot systemd unit
- `homestack-firstboot.sh` — unattended bootstrap runner
- `bootstrap.env.example` — env contract for first-boot execution

Companion runbook: `UNATTENDED_DEBIAN.md`.

### config/homestack.env

```bash
HOMESTACK_DIR=/path/to/homestack
APPDATA=/path/to/homestack/AppData
BACKUPS=/path/to/homestack/Backups
MEDIA=/path/to/homestack/Media
TZ=America/New_York
PUID=1000
PGID=1000
DOCKER_USER=1000:1000
HOMESTACK_APPS_REPO=https://github.com/filippvizvary/homestack-apps.git
```

## Key Patterns & Conventions

### Naming
- Library functions use module-specific prefixes: `db_`, `registry_`, `compose_cmd`, `generate_`
- Command files: `homestack/commands/<verb>.py`, each exports a Click command
- App directories: lowercase, alphanumeric, matching the `name:` field in `app.yaml`

### Error Handling
- `core.error()` + `sys.exit(1)` for fatal errors
- `db_log_action()` wrapped in try/except (never crashes)
- `install.py` has rollback cleanup on failure
- `backup.py` and `remove.py` use Docker fallbacks for permission errors

### Concurrency
- File-based locking via `fcntl.flock` (non-blocking)
- `homestack_lock` context manager wraps acquire/release
- Only mutating commands acquire the lock

### Interactive Detection
- `os.isatty(sys.stdin.fileno())` detects non-interactive sessions
- `--defaults` flag forces non-interactive mode
- Prevents `click.prompt()` from hanging in non-TTY environments

### Security
- Dedicated `homestack` system user owns all files
- `secrets.env` files are `chmod 600` and `.gitignored`
- `validate_path_component()` rejects `/` and `..`
- Passwords are alphanumeric only

### Docker Compose Patterns
- All operations go through `compose_cmd()` — never call `docker compose` directly
- Env file stacking: global → app config → app secrets
- Networks created as Docker external networks
- Volume mount paths pre-created to avoid root ownership

### Priority Ordering
- `priority` value in `app.yaml` (lower = starts first)
- Stop order is reversed
- Used by `start all`, `stop all`, `restart all`

### Config Tracking
- On install: config.env defaults saved to `config_overrides` table
- On update: `_merge_config()` preserves user edits, updates defaults

## Testing

### Test Structure

```
tests/
├── conftest.py              # Shared fixtures (tmp_homestack, etc.)
├── unit/
│   ├── test_core.py         # Path resolution, validation, locking, helpers
│   ├── test_db.py           # All db_ functions, CRUD, schema
│   ├── test_yaml_parser.py  # YAML loading, dataclass parsing
│   ├── test_secrets.py      # Password generation, file creation, append
│   └── test_registry.py     # Catalog find, list, search
└── fixtures/
    ├── sample.yaml          # Full-featured YAML fixture
    └── nosecrets.yaml       # Minimal YAML fixture
```

### Running Tests

```bash
# Activate venv
source .venv/bin/activate

# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest tests/unit/test_db.py

# Run specific test
pytest -k "test_db_init"
```

72 unit tests covering core, db, yaml_parser, secrets, and registry modules.

### Test Fixtures

The `tmp_homestack` fixture in `conftest.py`:
- Creates a temporary directory with the full HomeStack layout
- Sets `HOMESTACK_DIR` environment variable
- Calls `refresh_paths()` to update all module-level path constants
- Creates fake catalog with sample app definitions
- Initializes the database

## End-to-End Flows

### Install Flow
```
homestack install jellyfin
  → acquire_lock
  → registry_ensure (clone/pull catalog)
  → registry_find jellyfin → .cache/homestack-apps/apps/jellyfin/
  → is_installed jellyfin → False
  → yaml_get app.yaml port → 8096
  → check_port_available 8096
  → ensure_network (none for jellyfin)
  → ensure_dir AppData/jellyfin
  → copy compose.yaml, config.env → installed/jellyfin/
  → _precreate_volumes (parse compose.yaml volume mounts)
  → generate_secrets_file → installed/jellyfin/secrets.env
  → db_track_config_defaults
  → compose_cmd jellyfin up -d
  → run_health_checks (test.yaml → HTTP GET :8096/health)
  → db_set_installed jellyfin 10.11.5
  → db_log_action install
  → release_lock
```

### Update Flow
```
homestack update jellyfin
  → acquire_lock
  → _backup_app jellyfin (automatic pre-update backup)
  → registry_sync (pull latest catalog)
  → compare versions
  → _merge_config: preserve user edits, update defaults
  → copy new compose.yaml
  → append_new_secrets
  → compose_cmd pull
  → compose_cmd up -d
  → db_set_updated jellyfin <new_version>
  → db_log_action update
  → release_lock
```

### Backup Flow
```
homestack backup jellyfin
  → acquire_lock
  → check backup_strategy (live for jellyfin)
  → tar config → Backups/jellyfin-config-<ts>.tar.gz
  → tar data → Backups/jellyfin-data-<ts>.tar.gz
  → db_record_backup (config + data)
  → _rotate_backups (keep last 5 per type)
  → release_lock
```

## Known Limitations

1. **Single-host only** — no clustering or multi-node support
2. **No TLS/reverse proxy** — apps expose raw HTTP ports
3. **No dependency resolution** — apps don't declare dependencies on other apps
4. **No update notifications** — user must run `homestack update` manually
5. **Container-owned files** — some apps create files as internal users; handled via Docker fallbacks

## Branching Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable, released code. Tagged with version numbers (e.g., `v0.3.0`). |
| `dev` | Integration branch for the next release. All feature/fix branches merge here first. |
| `feat/*` | New features (e.g., `feat/config-edit`, `feat/dependency-resolution`) |
| `fix/*` | Bug fixes (e.g., `fix/lock-race-condition`) |
| `test/*` | Test additions or refactors |

### Workflow

```
feat/my-feature ──► dev ──► main (tagged release)
fix/my-bugfix   ──► dev ──► main
```

1. Create a branch from `dev` using the appropriate prefix
2. Make changes, push, and open a PR targeting `dev`
3. Once `dev` is stable and tested, PR `dev` → `main` and tag a release
4. Never commit directly to `main` or `dev`

### Cross-Repo Testing

When a CLI change affects how apps are consumed (e.g., changes to `compose_cmd()` or `generate_secrets_file()`), test against a local apps repo:

```bash
export HOMESTACK_APPS_REPO=/home/user/homestack-apps
homestack catalog update
homestack install immich --defaults
```

## Common Development Tasks

### Adding a new CLI command
1. Create `homestack/commands/<verb>.py` with a Click command
2. Register it in `homestack/cli.py` via `cli.add_command()`
3. Decide if it needs a lock (mutating = yes, read-only = no)

### Adding a new DB table
1. Add `CREATE TABLE IF NOT EXISTS` in `db_init()` in `homestack/db.py`
2. Add CRUD functions with `db_` prefix

### Modifying the install/update flow
1. Edit `homestack/commands/install.py` or `update.py`
2. Ensure rollback in install handles the new step
3. Update audit logging if adding new actions
4. Test with apps that have secrets and ones without

### Working with the catalog
1. App definitions live in the `homestack-apps` repo
2. Local clone is at `.cache/homestack-apps/`
3. To test locally, modify files in `.cache/homestack-apps/apps/<app>/`
4. `registry_sync()` will overwrite local changes on next pull

### Running on a VM
```bash
cd ~/homestack
python3 -m venv .venv
.venv/bin/pip install -e .
.venv/bin/homestack install uptimekuma --defaults
```
