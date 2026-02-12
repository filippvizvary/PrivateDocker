#!/usr/bin/env bats
# Unit tests for lib/db.sh

load '../test_helper'

setup() {
  setup_test_env
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_init
}

teardown() {
  teardown_test_env
}

# --- db_init ---

@test "db_init: creates all 5 tables" {
  local tables
  tables=$(sqlite3 "$DB_FILE" ".tables")
  [[ "$tables" == *"apps"* ]]
  [[ "$tables" == *"config_overrides"* ]]
  [[ "$tables" == *"backups"* ]]
  [[ "$tables" == *"health"* ]]
  [[ "$tables" == *"audit_log"* ]]
}

@test "db_init: is idempotent — running twice succeeds" {
  run db_init
  assert_success
}

# --- db_escape ---

@test "db_escape: escapes single quotes" {
  run db_escape "it's"
  assert_success
  assert_output "it''s"
}

@test "db_escape: leaves strings without quotes unchanged" {
  run db_escape "hello"
  assert_success
  assert_output "hello"
}

@test "db_escape: handles empty string" {
  run db_escape ""
  assert_success
  assert_output ""
}

# --- App lifecycle ---

@test "db_set_installed + db_get_installed_version roundtrip" {
  db_set_installed "testapp" "1.0.0"
  run db_get_installed_version "testapp"
  assert_success
  assert_output "1.0.0"
}

@test "db_is_installed: returns true for installed app" {
  db_set_installed "testapp" "1.0.0"
  run db_is_installed "testapp"
  assert_success
}

@test "db_is_installed: returns false for nonexistent app" {
  run db_is_installed "nonexistent"
  assert_failure
}

@test "db_get_install_date: returns ISO timestamp" {
  db_set_installed "testapp" "1.0.0"
  run db_get_install_date "testapp"
  assert_success
  # Should match YYYY-MM-DD HH:MM:SS format
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "db_set_catalog_version + db_get_catalog_version roundtrip" {
  db_set_installed "testapp" "1.0.0"
  db_set_catalog_version "testapp" "2.0.0"
  run db_get_catalog_version "testapp"
  assert_success
  assert_output "2.0.0"
}

@test "db_set_updated: updates version and sets updated_at" {
  db_set_installed "testapp" "1.0.0"
  db_set_updated "testapp" "1.1.0"
  run db_get_installed_version "testapp"
  assert_success
  assert_output "1.1.0"

  # updated_at should now be set
  local updated
  updated=$(db_query "SELECT updated_at FROM apps WHERE name = 'testapp';")
  [[ -n "$updated" ]]
}

@test "db_remove_app: deletes from apps, config_overrides, health" {
  db_set_installed "testapp" "1.0.0"
  db_update_health "testapp" "container1" "healthy"
  db_exec "INSERT INTO config_overrides (app, key, value) VALUES ('testapp', 'FOO', 'bar');"

  db_remove_app "testapp"

  run db_is_installed "testapp"
  assert_failure

  local config_count health_count
  config_count=$(db_query "SELECT COUNT(*) FROM config_overrides WHERE app = 'testapp';")
  health_count=$(db_query "SELECT COUNT(*) FROM health WHERE app = 'testapp';")
  [[ "$config_count" -eq 0 ]]
  [[ "$health_count" -eq 0 ]]
}

# --- Config tracking ---

@test "db_track_config_defaults: stores all keys from config file" {
  local config_file="${TEST_TMPDIR}/test_config.env"
  cat > "$config_file" <<'EOF'
# Comment line
APP_IMAGE=nginx:1.27
APP_PORT=8080
EXTRA_VAR=hello
EOF

  db_set_installed "testapp" "1.0.0"
  db_track_config_defaults "testapp" "$config_file"

  # Should have 3 entries
  local count
  count=$(db_query "SELECT COUNT(*) FROM config_overrides WHERE app = 'testapp';")
  [[ "$count" -eq 3 ]]
}

@test "db_is_config_modified: returns false when value matches default" {
  db_set_installed "testapp" "1.0.0"
  db_exec "INSERT INTO config_overrides (app, key, value, is_user_modified) VALUES ('testapp', 'PORT', '8080', 0);"

  # Same value as stored — NOT modified
  run db_is_config_modified "testapp" "PORT" "8080"
  assert_failure  # returns 1 = not modified
}

@test "db_is_config_modified: returns true when value differs from default" {
  db_set_installed "testapp" "1.0.0"
  db_exec "INSERT INTO config_overrides (app, key, value, is_user_modified) VALUES ('testapp', 'PORT', '8080', 0);"

  # Different value — IS modified
  run db_is_config_modified "testapp" "PORT" "9090"
  assert_success  # returns 0 = is modified
}

@test "db_mark_config_modified: sets is_user_modified flag" {
  db_set_installed "testapp" "1.0.0"
  db_exec "INSERT INTO config_overrides (app, key, value, is_user_modified) VALUES ('testapp', 'PORT', '8080', 0);"

  db_mark_config_modified "testapp" "PORT" "9090"

  local flag
  flag=$(db_query "SELECT is_user_modified FROM config_overrides WHERE app = 'testapp' AND key = 'PORT';")
  [[ "$flag" -eq 1 ]]
}

@test "db_get_modified_configs: returns only user-modified entries" {
  db_set_installed "testapp" "1.0.0"
  db_exec "INSERT INTO config_overrides (app, key, value, is_user_modified) VALUES ('testapp', 'PORT', '8080', 0);"
  db_exec "INSERT INTO config_overrides (app, key, value, is_user_modified) VALUES ('testapp', 'NAME', 'custom', 1);"

  run db_get_modified_configs "testapp"
  assert_success
  assert_output "NAME|custom"
}

# --- Backup tracking ---

@test "db_record_backup + db_list_backups roundtrip" {
  db_record_backup "testapp" "/backups/test.tar.gz" 1234 "config"

  run db_list_backups "testapp"
  assert_success
  [[ "$output" == *"test.tar.gz"* ]]
  [[ "$output" == *"1234"* ]]
  [[ "$output" == *"config"* ]]
}

@test "db_list_all_backups: returns entries from multiple apps" {
  db_record_backup "app1" "/backups/app1.tar.gz" 100 "config"
  db_record_backup "app2" "/backups/app2.tar.gz" 200 "data"

  run db_list_all_backups
  assert_success
  [[ "$output" == *"app1"* ]]
  [[ "$output" == *"app2"* ]]
}

@test "db_remove_backup: deletes by ID" {
  db_record_backup "testapp" "/backups/test.tar.gz" 1234 "config"

  local id
  id=$(db_query "SELECT id FROM backups LIMIT 1;")
  db_remove_backup "$id"

  local count
  count=$(db_query "SELECT COUNT(*) FROM backups;")
  [[ "$count" -eq 0 ]]
}

# --- Health tracking ---

@test "db_update_health + db_get_health roundtrip" {
  db_update_health "testapp" "container1" "healthy"

  run db_get_health "testapp"
  assert_success
  [[ "$output" == *"container1"* ]]
  [[ "$output" == *"healthy"* ]]
}

@test "db_update_health: upserts existing container status" {
  db_update_health "testapp" "container1" "starting"
  db_update_health "testapp" "container1" "healthy"

  local count
  count=$(db_query "SELECT COUNT(*) FROM health WHERE app = 'testapp' AND container = 'container1';")
  [[ "$count" -eq 1 ]]

  run db_get_health "testapp"
  assert_output --partial "healthy"
}

# --- Audit log ---

@test "db_log_action + db_get_audit_log roundtrip" {
  db_log_action "install" "testapp" "Installed version 1.0.0" 0

  run db_get_audit_log 5
  assert_success
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"testapp"* ]]
  [[ "$output" == *"Installed version 1.0.0"* ]]
}

@test "db_get_audit_log: respects limit" {
  db_log_action "install" "app1" "installed" 0
  db_log_action "install" "app2" "installed" 0
  db_log_action "install" "app3" "installed" 0

  run db_get_audit_log 2
  assert_success
  # Should have exactly 2 lines
  [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "db_log_action: records exit code" {
  db_log_action "error" "testapp" "Something failed" 1

  local exit_code
  exit_code=$(db_query "SELECT exit_code FROM audit_log WHERE action = 'error' LIMIT 1;")
  [[ "$exit_code" -eq 1 ]]
}
