#!/usr/bin/env bats
# Integration tests — full app lifecycle (requires Docker)
# Tests: install → status → stop → start → restart → backup → update → restore → remove

load '../test_helper'

TEST_APP="testapp"

setup_file() {
  # Create a persistent test environment for the whole file
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
  export HOMESTACK_BIN="${HOMESTACK_DIR}/bin/homestack"

  # Initialize DB
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_init
}

teardown_file() {
  # Clean up any leftover containers
  docker compose -f "${HOMESTACK_DIR}/installed/${TEST_APP}/compose.yaml" \
    down --remove-orphans 2>/dev/null || true

  docker compose -f "${HOMESTACK_DIR}/installed/testapp-nosecrets/compose.yaml" \
    down --remove-orphans 2>/dev/null || true

  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Install ---

@test "lifecycle: install testapp succeeds" {
  run "${HOMESTACK_BIN}" install "${TEST_APP}"
  echo "OUTPUT: $output" >&2
  assert_success

  # installed directory should exist
  [[ -d "${HOMESTACK_DIR}/installed/${TEST_APP}" ]]

  # compose.yaml copied
  [[ -f "${HOMESTACK_DIR}/installed/${TEST_APP}/compose.yaml" ]]

  # config.env copied
  [[ -f "${HOMESTACK_DIR}/installed/${TEST_APP}/config.env" ]]

  # secrets.env generated
  [[ -f "${HOMESTACK_DIR}/installed/${TEST_APP}/secrets.env" ]]

  # AppData directory created
  [[ -d "${HOMESTACK_DIR}/AppData/${TEST_APP}" ]]
}

@test "lifecycle: install creates DB entry" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"

  run db_is_installed "${TEST_APP}"
  assert_success

  run db_get_installed_version "${TEST_APP}"
  assert_success
  assert_output "1.0.0"
}

@test "lifecycle: install generated secrets file with correct key" {
  grep -q "^TEST_SECRET=" "${HOMESTACK_DIR}/installed/${TEST_APP}/secrets.env"
}

# --- Status ---

@test "lifecycle: status shows testapp running" {
  run "${HOMESTACK_BIN}" status
  assert_success
  [[ "$output" == *"testapp"* ]]
}

# --- Stop ---

@test "lifecycle: stop testapp succeeds" {
  run "${HOMESTACK_BIN}" stop "${TEST_APP}"
  assert_success
}

# --- Start ---

@test "lifecycle: start testapp succeeds" {
  run "${HOMESTACK_BIN}" start "${TEST_APP}"
  assert_success
}

# --- Restart ---

@test "lifecycle: restart testapp succeeds" {
  run "${HOMESTACK_BIN}" restart "${TEST_APP}"
  assert_success
}

# --- Backup ---

@test "lifecycle: backup testapp creates archives" {
  run "${HOMESTACK_BIN}" backup "${TEST_APP}"
  assert_success

  # Should have created backup files
  local backup_files
  backup_files=$(find "${HOMESTACK_DIR}/Backups" -name "${TEST_APP}*" -type f 2>/dev/null | wc -l)
  [[ "$backup_files" -gt 0 ]]
}

@test "lifecycle: backup recorded in database" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"

  run db_list_backups "${TEST_APP}"
  assert_success
  [[ -n "$output" ]]
}

# --- Update ---

@test "lifecycle: update testapp succeeds (same version)" {
  run "${HOMESTACK_BIN}" update "${TEST_APP}"
  assert_success
}

# --- Remove ---

@test "lifecycle: remove testapp succeeds" {
  run "${HOMESTACK_BIN}" remove "${TEST_APP}" <<< "n"
  assert_success

  # installed directory should be gone
  [[ ! -d "${HOMESTACK_DIR}/installed/${TEST_APP}" ]]
}

@test "lifecycle: remove cleans up database" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"

  run db_is_installed "${TEST_APP}"
  assert_failure
}
