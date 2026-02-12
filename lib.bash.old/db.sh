#!/bin/bash
# HomeStack — SQLite database layer
# Tracks installed apps, config overrides, backups, health, and audit log

DB_FILE="${HOMESTACK_DIR}/homestack.db"

# Initialize the database schema
db_init() {
  if ! command -v sqlite3 &>/dev/null; then
    error "sqlite3 is required but not installed."
    echo "  Install it with: sudo apt install sqlite3"
    exit 1
  fi

  sqlite3 "$DB_FILE" <<'SQL'
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
SQL
}

# Execute a SQL statement (INSERT, UPDATE, DELETE)
db_exec() {
  sqlite3 "$DB_FILE" "$1"
}

# Query and return results (SELECT)
db_query() {
  sqlite3 -separator '|' "$DB_FILE" "$1"
}

# --- App state ---

# Record a newly installed app
db_set_installed() {
  local app="$1" version="$2"
  db_exec "INSERT OR REPLACE INTO apps (name, installed_version, installed_at, status) VALUES ('${app}', '${version}', datetime('now'), 'installed');"
}

# Update catalog version for an app
db_set_catalog_version() {
  local app="$1" version="$2"
  db_exec "UPDATE apps SET catalog_version = '${version}' WHERE name = '${app}';"
}

# Record that an app was updated
db_set_updated() {
  local app="$1" version="$2"
  db_exec "UPDATE apps SET installed_version = '${version}', updated_at = datetime('now') WHERE name = '${app}';"
}

# Remove an app record
db_remove_app() {
  local app="$1"
  db_exec "DELETE FROM apps WHERE name = '${app}';"
  db_exec "DELETE FROM config_overrides WHERE app = '${app}';"
  db_exec "DELETE FROM health WHERE app = '${app}';"
}

# Get installed version for an app
db_get_installed_version() {
  db_query "SELECT installed_version FROM apps WHERE name = '${1}';"
}

# Get catalog version for an app
db_get_catalog_version() {
  db_query "SELECT catalog_version FROM apps WHERE name = '${1}';"
}

# Check if app exists in DB
db_is_installed() {
  local count
  count=$(db_query "SELECT COUNT(*) FROM apps WHERE name = '${1}';")
  [[ "$count" -gt 0 ]]
}

# Get install timestamp
db_get_install_date() {
  db_query "SELECT installed_at FROM apps WHERE name = '${1}';"
}

# --- Config tracking ---

# Store default config key-value pairs on install
db_track_config_defaults() {
  local app="$1" config_file="$2"
  [[ -f "$config_file" ]] || return 0
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    local key="${line%%=*}"
    local value="${line#*=}"
    # Remove surrounding quotes
    value="${value#\"}" ; value="${value%\"}"
    value="${value#\'}" ; value="${value%\'}"
    db_exec "INSERT OR REPLACE INTO config_overrides (app, key, value, is_user_modified) VALUES ('$(db_escape "$app")', '$(db_escape "$key")', '$(db_escape "$value")', 0);"
  done < "$config_file"
}

# Check if user has modified a config key from its default
db_is_config_modified() {
  local app="$1" key="$2" current_value="$3"
  local stored_value
  stored_value=$(db_query "SELECT value FROM config_overrides WHERE app = '$(db_escape "$app")' AND key = '$(db_escape "$key")';")
  if [[ -z "$stored_value" ]]; then
    # Key not tracked — treat as user-modified (don't overwrite)
    return 0
  fi
  [[ "$current_value" != "$stored_value" ]]
}

# Mark a config key as user-modified
db_mark_config_modified() {
  local app="$1" key="$2" value="$3"
  db_exec "UPDATE config_overrides SET value = '$(db_escape "$value")', is_user_modified = 1 WHERE app = '$(db_escape "$app")' AND key = '$(db_escape "$key")';"
}

# Get all user-modified config keys for an app
db_get_modified_configs() {
  db_query "SELECT key, value FROM config_overrides WHERE app = '$(db_escape "$1")' AND is_user_modified = 1;"
}

# --- Backup tracking ---

# Record a backup
db_record_backup() {
  local app="$1" path="$2" size="$3" type="${4:-full}"
  db_exec "INSERT INTO backups (app, path, size_bytes, type) VALUES ('$(db_escape "$app")', '$(db_escape "$path")', ${size}, '$(db_escape "$type")');"
}

# List backups for an app
db_list_backups() {
  local app="$1"
  db_query "SELECT id, path, size_bytes, created_at, type FROM backups WHERE app = '$(db_escape "$app")' ORDER BY created_at DESC;"
}

# List all backups
db_list_all_backups() {
  db_query "SELECT id, app, path, size_bytes, created_at, type FROM backups ORDER BY created_at DESC;"
}

# Remove a backup record
db_remove_backup() {
  db_exec "DELETE FROM backups WHERE id = ${1};"
}

# --- Health tracking ---

# Update container health status
db_update_health() {
  local app="$1" container="$2" status="$3"
  db_exec "INSERT OR REPLACE INTO health (app, container, status, checked_at) VALUES ('$(db_escape "$app")', '$(db_escape "$container")', '$(db_escape "$status")', datetime('now'));"
}

# Get health for an app
db_get_health() {
  db_query "SELECT container, status, checked_at FROM health WHERE app = '$(db_escape "$1")';"
}

# --- Audit log ---

# Log an action
db_log_action() {
  local action="$1" app="${2:-}" detail="${3:-}" exit_code="${4:-0}"
  db_exec "INSERT INTO audit_log (action, app, detail, exit_code) VALUES ('$(db_escape "$action")', '$(db_escape "$app")', '$(db_escape "$detail")', ${exit_code});"
}

# Get recent audit log entries
db_get_audit_log() {
  local limit="${1:-20}"
  db_query "SELECT timestamp, action, app, detail, exit_code FROM audit_log ORDER BY id DESC LIMIT ${limit};"
}

# --- Helpers ---

# Escape single quotes for SQL
db_escape() {
  echo "${1//\'/\'\'}"
}
