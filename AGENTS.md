# AGENTS.md — HomeStack CLI

> Comprehensive context file for AI coding agents working on this repository.

## Project Overview

**HomeStack** is a Bash CLI tool that manages self-hosted Docker Compose applications on a single Linux server. It provides install, update, backup, restore, and lifecycle management with SQLite-backed state tracking.

- **Language:** Bash (requires Bash 4+)
- **Version:** 0.2.0
- **License:** MIT
- **Owner:** filippvizvary (GitHub)
- **Dependencies:** `sqlite3`, `git`, `curl`, `docker` (with Compose v2 plugin), `flock`, `tar`, `grep`, `sed`, `awk`
- **Companion repo:** `homestack-apps` — community catalog of app definitions

## Architecture

```
User → bin/homestack (CLI entrypoint)
         ├── lib/core.sh      (shared utilities, compose_cmd, locking)
         ├── lib/db.sh         (SQLite abstraction layer)
         ├── lib/registry.sh   (catalog sync via git)
         ├── lib/secrets.sh    (secret generation)
         ├── lib/yaml.sh       (minimal YAML parser)
         └── lib/commands/     (one file per CLI command)
              ├── install.sh
              ├── update.sh
              ├── remove.sh
              ├── backup.sh
              ├── restore.sh
              ├── start.sh
              ├── stop.sh
              ├── restart.sh
              ├── status.sh
              ├── list.sh
              ├── search.sh
              └── catalog.sh
```

### Data Flow

```
homestack-apps repo (GitHub)
    ↓ git clone/pull
.cache/homestack-apps/apps/<app>/
    ├── app.yaml       (manifest: ports, secrets, networks, priority)
    ├── compose.yaml   (Docker Compose definition)
    └── config.env     (default image tags + config)
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
├── bin/homestack           # CLI entrypoint (symlinked to /usr/local/bin)
├── lib/
│   ├── core.sh             # Colors, paths, compose_cmd, locking, helpers
│   ├── db.sh               # SQLite CRUD for all 5 tables
│   ├── registry.sh         # Git-based catalog sync
│   ├── secrets.sh          # Password generation + secrets.env management
│   ├── yaml.sh             # Minimal grep/sed YAML parser
│   └── commands/           # One file per command, each exports cmd_run()
├── config/
│   └── homestack.env       # Global config (paths, timezone, UID/GID)
├── setup.sh                # Interactive installer (Docker, deps, config)
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
├── homestack.db            # SQLite database
└── .lock                   # flock file for concurrency control
```

## File-by-File Reference

### bin/homestack (~60 lines)

CLI entrypoint. Sources all library files, calls `db_init`, then dispatches commands via a `case` statement.

**Key behaviors:**
- Sets `HOMESTACK_DIR` to the script's parent directory
- Sources: `core.sh`, `db.sh`, `registry.sh`, `secrets.sh`, `yaml.sh`
- Calls `db_init` on every invocation (creates tables if missing)
- ERR trap: logs failed commands to `audit_log` table
- Command dispatch: sources `lib/commands/<cmd>.sh` and calls `cmd_run "$@"`
- Shows `print_help` for unknown commands or no arguments

**Command dispatch table:**

| Command | File | Lock Required |
|---------|------|---------------|
| `install` | `commands/install.sh` | Yes |
| `update` | `commands/update.sh` | Yes |
| `remove` | `commands/remove.sh` | Yes |
| `backup` | `commands/backup.sh` | Yes |
| `restore` | `commands/restore.sh` | Yes |
| `start` | `commands/start.sh` | Yes |
| `stop` | `commands/stop.sh` | Yes |
| `restart` | `commands/restart.sh` | Yes |
| `status` | `commands/status.sh` | No |
| `list` | `commands/list.sh` | No |
| `search` | `commands/search.sh` | No |
| `catalog` | `commands/catalog.sh` | No |

### lib/core.sh (~150 lines)

Shared utilities sourced by every command.

**Global variables:**
- `HOMESTACK_DIR` — repo root (set by `bin/homestack`)
- `INSTALLED_DIR` — `$HOMESTACK_DIR/installed`
- `CONFIG_FILE` — `$HOMESTACK_DIR/config/homestack.env`
- `DB_FILE` — `$HOMESTACK_DIR/homestack.db`
- `LOCK_FILE` — `$HOMESTACK_DIR/.lock`
- Color codes: `RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `BOLD`, `NC`

**Functions:**

| Function | Purpose |
|----------|---------|
| `compose_cmd app args...` | Runs `docker compose` with stacked `--env-file` flags and `-f` pointing to the app's compose.yaml. Central function for ALL Docker operations. |
| `get_installed_apps` | Lists installed apps by scanning `$INSTALLED_DIR/*/compose.yaml` |
| `acquire_lock` | Uses `flock` (fd 9) on `.lock` file. Non-blocking — exits with error if lock held. |
| `release_lock` | Releases fd 9. |
| `validate_path_component str` | Rejects strings with `/`, `..`, or empty — prevents path traversal. |
| `check_port_available port` | Uses `ss -tlnp` to check if a TCP port is in use. |
| `print_help` | Prints CLI usage summary with all commands. |

### lib/db.sh (~219 lines)

Full SQLite abstraction layer. All queries go through `sqlite3 "$DB_FILE"`.

**Functions:**

| Function | Purpose |
|----------|---------|
| `db_init` | Creates all 5 tables with `CREATE TABLE IF NOT EXISTS`. Called on every CLI invocation. |
| `db_escape str` | Escapes single quotes for SQL injection prevention (`'` → `''`). |
| `db_add_app name version` | INSERT into `apps` table with `installed_at` timestamp. |
| `db_remove_app name` | DELETE from `apps`, `config_overrides`, `health` for the given app. |
| `db_get_app name` | SELECT from `apps`, returns pipe-delimited row. |
| `db_update_app_version name version` | UPDATE `installed_version` and `updated_at`. |
| `db_set_catalog_version name version` | UPDATE `catalog_version` field. |
| `db_set_app_status name status` | UPDATE `status` field (running/stopped/error). |
| `db_save_config_default app key value` | INSERT OR IGNORE into `config_overrides` (only saves initial defaults). |
| `db_get_config_default app key` | SELECT `value` from `config_overrides` WHERE `is_user_modified=0`. |
| `db_mark_config_modified app key` | UPDATE `is_user_modified=1`. |
| `db_add_backup app path size type` | INSERT into `backups`. |
| `db_get_backups app` | SELECT from `backups` ORDER BY `created_at DESC`. |
| `db_delete_backup id` | DELETE from `backups` by id. |
| `db_update_health app container status` | INSERT OR REPLACE into `health`. |
| `db_add_audit action app detail exit_code` | INSERT into `audit_log`. |

**Database Schema (SQLite):**

```sql
CREATE TABLE apps (
    name            TEXT PRIMARY KEY,
    installed_version TEXT,
    catalog_version TEXT,
    installed_at    TEXT,       -- ISO 8601
    updated_at      TEXT,       -- ISO 8601
    status          TEXT        -- running | stopped | error
);

CREATE TABLE config_overrides (
    app             TEXT,
    key             TEXT,
    value           TEXT,
    is_user_modified INTEGER DEFAULT 0,  -- 0=default, 1=user-edited
    PRIMARY KEY (app, key)
);

CREATE TABLE backups (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    app             TEXT,
    path            TEXT,
    size_bytes      INTEGER,
    created_at      TEXT,       -- ISO 8601
    type            TEXT        -- config | data
);

CREATE TABLE health (
    app             TEXT,
    container       TEXT,
    status          TEXT,       -- healthy | unhealthy | starting | unknown
    checked_at      TEXT,       -- ISO 8601
    PRIMARY KEY (app, container)
);

CREATE TABLE audit_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       TEXT,       -- ISO 8601
    action          TEXT,       -- install | update | remove | backup | restore | error
    app             TEXT,
    detail          TEXT,
    exit_code       INTEGER
);
```

### lib/registry.sh (~101 lines)

Manages the local clone of the `homestack-apps` catalog.

**Global variables:**
- `CATALOG_DIR` — `$HOMESTACK_DIR/.cache/homestack-apps`
- `APPS_DIR` — `$CATALOG_DIR/apps` (set after sync)

**Functions:**

| Function | Purpose |
|----------|---------|
| `registry_sync` | Clones or pulls the catalog repo. Uses `HOMESTACK_APPS_REPO` from homestack.env. |
| `registry_ensure` | Calls `registry_sync` if `APPS_DIR` doesn't exist. |
| `registry_list` | Lists all app directories in the catalog. |
| `registry_find app` | Returns path to a specific app dir, or fails. |
| `registry_search query` | Grep-based search across app.yaml files for name/description matches. |

### lib/secrets.sh (~133 lines)

Generates and manages `secrets.env` files.

**Functions:**

| Function | Purpose |
|----------|---------|
| `generate_password length` | Generates alphanumeric password from `/dev/urandom`. No special characters (avoids escaping issues in env files). |
| `generate_secrets_file app_yaml_path output_path` | Parses secrets from `app.yaml`, generates passwords for `generate: true` entries, uses defaults for others, writes to `secrets.env` with `chmod 600`. |
| `append_new_secrets app_yaml_path secrets_file` | During updates: adds any NEW secret keys from catalog that don't exist in the current secrets.env. Does NOT overwrite existing secrets. |

### lib/yaml.sh (~64 lines)

Minimal YAML parser using grep/sed/awk. Does NOT handle all YAML — only the subset used in app.yaml files.

**Functions:**

| Function | Purpose |
|----------|---------|
| `yaml_get file key` | Gets a scalar value: `grep "^key:" file \| sed ...`. |
| `yaml_get_array file key` | Gets a YAML list as newline-delimited values. Handles `- item` syntax. |
| `yaml_parse_secrets file` | Parses the `secrets:` block into structured output. Returns lines like `KEY\|prompt\|default\|generate\|length`. |

**Limitations:**
- No nested object support beyond secrets
- No multi-line values
- No anchors/aliases
- Assumes clean formatting (key at start of line, space after colon)

### lib/commands/ — Command Files

Every command file exports a single function `cmd_run()` that receives remaining CLI args.

#### install.sh (~140 lines)
1. Takes app name argument
2. Calls `registry_ensure` then `registry_find` to locate the app
3. Checks if already installed (`db_get_app`)
4. Reads `app.yaml` for port, networks, appdata_dirs, media_dirs
5. Checks port availability (`check_port_available`)
6. Creates Docker networks if needed
7. Creates appdata and media directories
8. Copies `compose.yaml` and `config.env` to `installed/<app>/`
9. Generates `secrets.env` via `generate_secrets_file`
10. Saves all config.env defaults to DB (`db_save_config_default`)
11. Starts the app via `compose_cmd up -d`
12. Records in DB (`db_add_app`) and audit log
13. **Rollback trap:** On failure, cleans up installed dir, networks, and DB entry

#### update.sh (~138 lines)
1. Creates automatic backup before updating
2. Syncs catalog (`registry_sync`)
3. Compares installed version vs catalog version
4. `merge_config()`: Reads new config.env, compares each key against DB-stored defaults — if user hasn't modified a key, updates it to the new default; if user modified it, preserves their value
5. Updates compose.yaml from catalog
6. `append_new_secrets()`: Adds any new secret keys without overwriting existing ones
7. Pulls new images and recreates containers
8. Updates DB version and audit log

#### remove.sh (~75 lines)
1. Stops containers via `compose_cmd down`
2. Removes Docker networks if they become unused
3. Optionally deletes AppData (prompts user with `-y` flag to skip)
4. Removes `installed/<app>/` directory
5. Cleans up DB: `db_remove_app`

#### backup.sh (~128 lines)
1. Reads `backup_strategy` from `app.yaml` (stop or live)
2. If `stop`: stops containers, backs up, restarts
3. Creates two separate tar archives:
   - `<app>-config-<timestamp>.tar.gz` — the `installed/<app>/` dir
   - `<app>-data-<timestamp>.tar.gz` — the `AppData/<app>/` dir
4. Records both in DB (`db_add_backup`)
5. Rotation: keeps `KEEP_LAST` (default 5) backups per app per type, deletes older
6. Supports `all` argument to back up every installed app

#### restore.sh (~182 lines)
1. Queries DB for available backups
2. Interactive selection (numbered list)
3. Type-aware extraction (config vs data go to different directories)
4. Restarts containers after restore

#### restart.sh (~78 lines)
- Restarts one app or all apps
- Uses `compose_cmd restart` (not stop+start)
- Priority-ordered when restarting all

#### status.sh (~69 lines)
- Runs `compose_cmd ps` and parses tab-delimited output
- Color-codes status (green=running, red=exited, yellow=other)
- Caches health status in DB via `db_update_health`

#### start.sh (~61 lines) / stop.sh (~44 lines)
- Start/stop one or all apps
- Priority ordering: lower number starts first, stops last (reverse)
- Uses `compose_cmd up -d` / `compose_cmd down`

#### list.sh (~32 lines)
- Lists installed apps with version from DB

#### search.sh (~35 lines)
- Searches catalog app.yaml files for query string

#### catalog.sh (~47 lines)
- Lists all available apps in the catalog with version/description

### setup.sh (~370 lines)

Interactive first-run installer. Handles:
1. Auto-installs dependencies: `sqlite3`, `git`, `curl`
2. Installs Docker via `get.docker.com` if missing
3. Installs Docker Compose plugin (`docker-compose-plugin`) via apt/dnf/yum
4. Creates a dedicated `homestack` system user and group:
   - System user with `--no-login` shell, home dir set to install path
   - Added to `docker` group for container management
   - Calling user (`SUDO_USER`) added to `homestack` group for CLI access
5. Interactive config: asks for APPDATA, BACKUPS, MEDIA paths, timezone, PUID/PGID
   - PUID/PGID default to the `homestack` user's UID/GID
6. Writes `config/homestack.env`
7. Initializes SQLite database
8. Syncs catalog repo
9. Sets ownership (`homestack:homestack`) and permissions (`2775` setgid) on all directories
   - `secrets.env` files: `chmod 640`
   - `homestack.db`: `chmod 660`
10. Creates CLI symlink at `/usr/local/bin/homestack`

Also supports `curl -fsSL <url> | sudo bash` one-liner install (clones the repo first).

### config/homestack.env

Global config values available to all compose files:

```bash
HOMESTACK_DIR=/path/to/homestack
APPDATA=/path/to/homestack/AppData     # or custom path
BACKUPS=/path/to/homestack/Backups
MEDIA=/path/to/homestack/Media
TZ=America/New_York                     # or user's timezone
PUID=1000
PGID=1000
DOCKER_USER=1000:1000                   # derived from PUID:PGID
HOMESTACK_APPS_REPO=https://github.com/filippvizvary/homestack-apps.git
```

## Key Patterns & Conventions

### Naming
- Library functions are prefixed by module: `db_`, `registry_`, `yaml_`, `generate_`, `compose_`
- Command files: `lib/commands/<verb>.sh`, each exports `cmd_run()`
- App directories: lowercase, alphanumeric, matching the `name:` field in `app.yaml`

### Error Handling
- All files use `set -euo pipefail` (strict mode)
- ERR trap in `bin/homestack` logs failures to `audit_log`
- `install.sh` has a dedicated rollback trap that cleans up on failure
- Functions `die` or `echo >&2` + `return 1` for errors

### Concurrency
- File-based locking via `flock` on `$HOMESTACK_DIR/.lock` (file descriptor 9)
- Non-blocking: if lock is held, exits immediately with an error
- Only mutating commands (install, update, remove, backup, restore, start, stop, restart) acquire the lock
- Read-only commands (status, list, search, catalog) run without locks

### Security
- Dedicated `homestack` system user owns all files — no login shell, least-privilege
- Calling user added to `homestack` group for CLI access
- Directories use setgid (`2775`) so new files inherit the group
- `secrets.env` files are `chmod 640` and listed in `.gitignore`
- `homestack.db` is `chmod 660` and in `.gitignore`
- `validate_path_component()` rejects `/` and `..` to prevent path traversal
- `db_escape()` prevents SQL injection in all DB operations
- Passwords are alphanumeric only (no special chars that could break env file parsing)

### Docker Compose Patterns
- All compose operations go through `compose_cmd()` — never call `docker compose` directly
- Env file stacking: global → app config → app secrets (via `--env-file` flags)
- Networks are created as Docker external networks, shared across apps
- Containers typically use `user: ${DOCKER_USER}` or `PUID`/`PGID` env vars

### Priority Ordering
- Each app has a `priority` value (integer) in its `app.yaml`
- Lower priority = starts first (e.g., databases before apps)
- Stop order is reversed (apps stop before databases)
- Used by `start all`, `stop all`, `restart all`

### Config Tracking
- On install: all config.env key=value pairs are saved to `config_overrides` table as defaults
- On update: `merge_config()` compares current values against stored defaults
  - If value matches default → user hasn't changed it → safe to update
  - If value differs from default → user customized it → preserve their value → mark `is_user_modified=1`

### Catalog Caching
- homestack-apps repo is cloned to `.cache/homestack-apps/`
- `registry_sync()` does `git pull` if already cloned
- App data is read directly from the clone (no DB caching of catalog data)
- `catalog_version` in the DB is updated on install/update from `app.yaml`

## End-to-End Flows

### Install Flow
```
homestack install jellyfin
  → acquire_lock
  → registry_ensure (clone/pull catalog)
  → registry_find jellyfin → .cache/homestack-apps/apps/jellyfin/
  → db_get_app jellyfin → not found (good)
  → yaml_get app.yaml port → 8096
  → check_port_available 8096
  → yaml_get_array app.yaml networks → (none for jellyfin)
  → yaml_get_array app.yaml appdata_dirs → jellyfin
  → mkdir -p AppData/jellyfin
  → cp compose.yaml, config.env → installed/jellyfin/
  → generate_secrets_file → installed/jellyfin/secrets.env (empty for jellyfin)
  → save config.env defaults to DB (db_save_config_default)
  → compose_cmd jellyfin up -d
  → db_add_app jellyfin 10.11.5
  → db_add_audit install jellyfin "Installed version 10.11.5" 0
  → release_lock
```

### Update Flow
```
homestack update jellyfin
  → acquire_lock
  → backup jellyfin (automatic pre-update backup)
  → registry_sync (pull latest catalog)
  → compare versions: installed_version vs yaml_get version
  → merge_config: for each key in new config.env:
      - db_get_config_default jellyfin KEY → old default
      - compare current value in installed config.env
      - if current == old default → update to new value
      - if current != old default → keep user's value, db_mark_config_modified
  → cp new compose.yaml → installed/jellyfin/
  → append_new_secrets (adds missing keys only)
  → compose_cmd jellyfin pull
  → compose_cmd jellyfin up -d
  → db_update_app_version jellyfin <new_version>
  → db_add_audit update jellyfin "Updated to <new_version>" 0
  → release_lock
```

### Backup Flow
```
homestack backup jellyfin
  → acquire_lock
  → check backup_strategy (live for jellyfin)
  → tar -czf Backups/jellyfin-config-<ts>.tar.gz installed/jellyfin/
  → tar -czf Backups/jellyfin-data-<ts>.tar.gz AppData/jellyfin/
  → db_add_backup jellyfin <path> <size> config
  → db_add_backup jellyfin <path> <size> data
  → rotate: keep last 5 config + 5 data backups, delete older (DB + files)
  → release_lock
```

### Restore Flow
```
homestack restore jellyfin
  → acquire_lock
  → db_get_backups jellyfin → list backups
  → user selects backup interactively
  → stop containers (compose_cmd down)
  → extract tar to appropriate directory (config→installed/, data→AppData/)
  → start containers (compose_cmd up -d)
  → db_add_audit restore jellyfin "Restored from <backup>" 0
  → release_lock
```

## Testing

No automated test suite exists. Manual testing workflow:

```bash
# Full lifecycle test
homestack install jellyfin
homestack status jellyfin
homestack backup jellyfin
homestack update jellyfin
homestack restore jellyfin
homestack stop jellyfin
homestack start jellyfin
homestack restart jellyfin
homestack remove jellyfin

# Read-only commands
homestack list
homestack catalog
homestack search media

# Verify DB state
sqlite3 homestack.db "SELECT * FROM apps;"
sqlite3 homestack.db "SELECT * FROM audit_log ORDER BY id DESC LIMIT 10;"
sqlite3 homestack.db "SELECT * FROM backups;"
```

## Known Limitations

1. **No automated tests** — testing is manual only
2. **YAML parser is fragile** — only handles the subset used in app.yaml; no nested objects, multi-line values, or anchors
3. **Single-host only** — no clustering or multi-node support
4. **No TLS/reverse proxy** — apps expose raw HTTP ports
5. **No dependency resolution** — apps don't declare dependencies on other apps
6. **SQLite concurrent access** — flock prevents concurrent CLI runs, but SQLite itself has limited concurrent write support
7. **No update notifications** — user must run `homestack update` manually to check for new versions

## Common Development Tasks

### Adding a new CLI command
1. Create `lib/commands/<verb>.sh` with a `cmd_run()` function
2. Add the case entry in `bin/homestack`
3. Update `print_help` in `lib/core.sh`
4. Decide if it needs a lock (mutating = yes, read-only = no)

### Adding a new DB table
1. Add `CREATE TABLE IF NOT EXISTS` in `db_init()` in `lib/db.sh`
2. Add CRUD functions with `db_` prefix
3. Use `db_escape()` for all string values in queries

### Modifying the install/update flow
1. Edit `lib/commands/install.sh` or `lib/commands/update.sh`
2. Ensure rollback trap in install handles the new step
3. Update audit logging if adding new actions
4. Test with at least one app that has secrets and one without

### Working with the catalog
1. App definitions live in the `homestack-apps` repo, not here
2. The local clone is at `.cache/homestack-apps/`
3. To test catalog changes locally, modify files in `.cache/homestack-apps/apps/<app>/`
4. `registry_sync()` will overwrite local changes on next pull
