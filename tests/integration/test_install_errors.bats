#!/usr/bin/env bats
# Integration tests — install error handling & edge cases

load '../test_helper'

HOMESTACK_BIN="${PROJECT_DIR}/bin/homestack"

setup_file() {
  export TEST_TMPDIR="$(mktemp -d)"
  export HOMESTACK_DIR="$TEST_TMPDIR"
  export DB_FILE="${HOMESTACK_DIR}/homestack.db"

  mkdir -p "${HOMESTACK_DIR}/installed"
  mkdir -p "${HOMESTACK_DIR}/AppData"
  mkdir -p "${HOMESTACK_DIR}/Backups"
  mkdir -p "${HOMESTACK_DIR}/Media"
  mkdir -p "${HOMESTACK_DIR}/config"
  mkdir -p "${HOMESTACK_DIR}/.cache/homestack-apps/apps"

  # Copy fixture catalog
  local fixtures="${BATS_TEST_DIRNAME}/../fixtures/catalog/apps"
  cp -r "$fixtures"/* "${HOMESTACK_DIR}/.cache/homestack-apps/apps/"

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

  cp -r "${PROJECT_DIR}/bin" "${HOMESTACK_DIR}/"
  cp -r "${PROJECT_DIR}/lib" "${HOMESTACK_DIR}/"
  chmod +x "${HOMESTACK_DIR}/bin/homestack"

  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_init
}

teardown_file() {
  # Clean up any containers that might have been started
  docker compose -f "${HOMESTACK_DIR}/installed/testapp/compose.yaml" \
    down --remove-orphans 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Missing arguments ---

@test "errors: install with no app name fails" {
  run "${HOMESTACK_BIN}" install
  assert_failure
}

@test "errors: remove with no app name fails" {
  run "${HOMESTACK_BIN}" remove
  assert_failure
}

@test "errors: stop with no app name fails" {
  run "${HOMESTACK_BIN}" stop
  assert_failure
}

@test "errors: start with no app name fails" {
  run "${HOMESTACK_BIN}" start
  assert_failure
}

# --- Nonexistent app ---

@test "errors: install nonexistent app fails" {
  run "${HOMESTACK_BIN}" install "zzz_no_such_app"
  assert_failure
}

@test "errors: status of nonexistent app fails" {
  run "${HOMESTACK_BIN}" status "zzz_no_such_app"
  assert_failure
}

# --- Path traversal ---

@test "errors: install rejects path traversal (..)" {
  run "${HOMESTACK_BIN}" install "../etc"
  assert_failure
}

@test "errors: install rejects slash in name" {
  run "${HOMESTACK_BIN}" install "foo/bar"
  assert_failure
}

@test "errors: install rejects empty name" {
  run "${HOMESTACK_BIN}" install ""
  assert_failure
}

# --- Already installed ---

@test "errors: install already-installed app fails" {
  # First install should succeed
  run "${HOMESTACK_BIN}" install testapp
  assert_success

  # Second install should fail
  run "${HOMESTACK_BIN}" install testapp
  assert_failure

  # Cleanup
  echo "n" | "${HOMESTACK_BIN}" remove testapp 2>/dev/null || true
  docker compose -f "${HOMESTACK_DIR}/installed/testapp/compose.yaml" \
    down --remove-orphans 2>/dev/null || true
}

# --- Unknown command ---

@test "errors: unknown command shows help" {
  run "${HOMESTACK_BIN}" foobar
  assert_success
  assert_output --partial "Usage"
}
