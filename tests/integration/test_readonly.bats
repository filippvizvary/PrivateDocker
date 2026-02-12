#!/usr/bin/env bats
# Integration tests — read-only commands (no Docker mutations required)

load '../test_helper'

HOMESTACK_BIN="${PROJECT_DIR}/bin/homestack"

setup_file() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOMESTACK_DIR="$TEST_TMPDIR"
  export DB_FILE="${HOMESTACK_DIR}/homestack.db"

  # Set up directory structure
  mkdir -p "${HOMESTACK_DIR}/installed"
  mkdir -p "${HOMESTACK_DIR}/AppData"
  mkdir -p "${HOMESTACK_DIR}/Backups"
  mkdir -p "${HOMESTACK_DIR}/Media"
  mkdir -p "${HOMESTACK_DIR}/config"
  mkdir -p "${HOMESTACK_DIR}/.cache/homestack-apps/apps"

  # Copy fixture catalog
  local fixtures="${BATS_TEST_DIRNAME}/../fixtures/catalog/apps"
  cp -r "$fixtures"/* "${HOMESTACK_DIR}/.cache/homestack-apps/apps/"

  # Write homestack.env
  cat > "${HOMESTACK_DIR}/config/homestack.env" <<EOF
HOMESTACK_DIR=${HOMESTACK_DIR}
APPDATA=${HOMESTACK_DIR}/AppData
BACKUPS=${HOMESTACK_DIR}/Backups
MEDIA=${HOMESTACK_DIR}/Media
TZ=UTC
PUID=1000
PGID=1000
DOCKER_USER=1000:1000
HOMESTACK_APPS_REPO=file:///dev/null
EOF

  # Copy scripts
  cp -r "${PROJECT_DIR}/bin" "${HOMESTACK_DIR}/"
  cp -r "${PROJECT_DIR}/lib" "${HOMESTACK_DIR}/"
  chmod +x "${HOMESTACK_DIR}/bin/homestack"

  # Initialize DB
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_init
}

teardown_file() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Version ---

@test "readonly: version prints version string" {
  run "${HOMESTACK_BIN}" version
  assert_success
  assert_output --partial "0.2.0"
}

# --- Help ---

@test "readonly: help prints usage" {
  run "${HOMESTACK_BIN}" help
  assert_success
  assert_output --partial "install"
  assert_output --partial "remove"
  assert_output --partial "status"
}

@test "readonly: no arguments prints help" {
  run "${HOMESTACK_BIN}"
  assert_success
  assert_output --partial "Usage"
}

# --- List ---

@test "readonly: list with no apps installed shows nothing or header" {
  run "${HOMESTACK_BIN}" list
  assert_success
}

@test "readonly: list after mock install shows app" {
  # Manually insert an app record
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_set_installed "fakeapp" "1.0.0"

  run "${HOMESTACK_BIN}" list
  assert_success
  assert_output --partial "fakeapp"

  # Cleanup
  db_remove_app "fakeapp"
}

# --- Catalog ---

@test "readonly: catalog lists available apps" {
  run "${HOMESTACK_BIN}" catalog
  assert_success
  assert_output --partial "testapp"
}

# --- Search ---

@test "readonly: search finds matching app" {
  run "${HOMESTACK_BIN}" search testapp
  assert_success
  assert_output --partial "testapp"
}

@test "readonly: search with no results" {
  run "${HOMESTACK_BIN}" search "zzz_nonexistent_zzz"
  # May return success with no output or failure — both acceptable
  refute_output --partial "Error"
}

@test "readonly: search without query shows error or usage" {
  run "${HOMESTACK_BIN}" search
  # Should fail or show usage — at minimum not crash
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# --- Log (audit log) ---

@test "readonly: log command returns output" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_log_action "test" "testapp" "test entry" 0

  run "${HOMESTACK_BIN}" log
  assert_success
  assert_output --partial "testapp"
}
