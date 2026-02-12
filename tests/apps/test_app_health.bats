#!/usr/bin/env bats
# App health tests — installs a real app and validates it via test.yaml
#
# Usage:
#   APP=jellyfin bats tests/apps/test_app_health.bats
#   APP=testapp  bats tests/apps/test_app_health.bats
#
# Requires: Docker running, test.yaml present for the app

load '../test_helper'

HOMESTACK_BIN="${PROJECT_DIR}/bin/homestack"

# ── Resolve which app and catalog to use ──

setup_file() {
  : "${APP:?APP environment variable must be set (e.g. APP=jellyfin)}"

  export TEST_TMPDIR="$(mktemp -d)"
  export HOMESTACK_DIR="$TEST_TMPDIR"
  export DB_FILE="${HOMESTACK_DIR}/homestack.db"

  # Create dirs
  mkdir -p "${HOMESTACK_DIR}/installed"
  mkdir -p "${HOMESTACK_DIR}/AppData"
  mkdir -p "${HOMESTACK_DIR}/Backups"
  mkdir -p "${HOMESTACK_DIR}/Media"
  mkdir -p "${HOMESTACK_DIR}/config"
  mkdir -p "${HOMESTACK_DIR}/.cache/homestack-apps/apps"

  # Determine catalog source: fixture catalog or real homestack-apps
  local fixture_app="${BATS_TEST_DIRNAME}/../fixtures/catalog/apps/${APP}"
  local real_app=""

  # Try to find real homestack-apps repo
  if [[ -d "${PROJECT_DIR}/../homestack-apps/apps/${APP}" ]]; then
    real_app="${PROJECT_DIR}/../homestack-apps/apps/${APP}"
  fi

  if [[ -d "$fixture_app" ]]; then
    cp -r "$fixture_app" "${HOMESTACK_DIR}/.cache/homestack-apps/apps/"
  elif [[ -n "$real_app" ]]; then
    cp -r "$real_app" "${HOMESTACK_DIR}/.cache/homestack-apps/apps/"
  else
    echo "ERROR: App '${APP}' not found in fixtures or homestack-apps catalog" >&2
    return 1
  fi

  # Locate the test.yaml
  local app_dir="${HOMESTACK_DIR}/.cache/homestack-apps/apps/${APP}"
  export TEST_YAML="${app_dir}/test.yaml"

  if [[ ! -f "$TEST_YAML" ]]; then
    echo "ERROR: No test.yaml found for app '${APP}'" >&2
    return 1
  fi

  # Write homestack.env
  cat > "${HOMESTACK_DIR}/config/homestack.env" <<EOF
HOMESTACK_DIR=${HOMESTACK_DIR}
APPDATA=${HOMESTACK_DIR}/AppData
BACKUPS=${HOMESTACK_DIR}/Backups
MEDIA=${HOMESTACK_DIR}/Media
TZ=UTC
PUID=$(id -u)
PGID=$(id -g)
DOCKER_USER=$(id -u):$(id -g)
HOMESTACK_APPS_REPO=file:///dev/null
EOF

  # Copy scripts
  cp -r "${PROJECT_DIR}/bin" "${HOMESTACK_DIR}/"
  cp -r "${PROJECT_DIR}/lib" "${HOMESTACK_DIR}/"
  chmod +x "${HOMESTACK_DIR}/bin/homestack"

  # Init DB
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  db_init

  # Read startup_time from test.yaml
  export STARTUP_TIME
  STARTUP_TIME=$(yaml_get "$TEST_YAML" "startup_time")
  STARTUP_TIME="${STARTUP_TIME:-15}"
}

teardown_file() {
  # Always try to remove the app
  "${HOMESTACK_BIN}" stop "${APP}" 2>/dev/null || true
  docker compose -f "${HOMESTACK_DIR}/installed/${APP}/compose.yaml" \
    down --remove-orphans -v 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# ── Test: Install ──

@test "${APP}: install succeeds" {
  run "${HOMESTACK_BIN}" install "${APP}"
  assert_success
}

# ── Test: Container health (wait for startup_time) ──

@test "${APP}: containers become healthy within startup_time" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"

  local elapsed=0
  local ready=false
  local interval=3

  while [[ $elapsed -lt $STARTUP_TIME ]]; do
    # Check if all containers are running
    local output
    output=$(compose_cmd "${APP}" ps --format '{{.Status}}' 2>/dev/null || true)

    if [[ -n "$output" ]] && ! echo "$output" | grep -qiE "starting|unhealthy|exited|dead|created"; then
      ready=true
      break
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  [[ "$ready" == "true" ]]
}

# ── Test: HTTP health checks from test.yaml ──

@test "${APP}: HTTP health checks pass" {
  source "${PROJECT_DIR}/lib/yaml.sh"

  local checks
  checks=$(yaml_parse_health_checks "$TEST_YAML")

  [[ -z "$checks" ]] && skip "No health_checks defined in test.yaml"

  local failures=0

  while IFS='|' read -r url method expected_status body_contains timeout; do
    [[ -z "$url" ]] && continue

    method="${method:-GET}"
    expected_status="${expected_status:-200}"
    timeout="${timeout:-10}"

    # Perform HTTP request
    local http_code body
    body=$(mktemp)

    http_code=$(curl -s -o "$body" -w '%{http_code}' \
      -X "${method}" \
      --max-time "${timeout}" \
      --insecure \
      "${url}" 2>/dev/null) || http_code="000"

    # Check status code
    if [[ "$http_code" != "$expected_status" ]]; then
      echo "FAIL: ${method} ${url} → got ${http_code}, expected ${expected_status}" >&2
      failures=$((failures + 1))
    fi

    # Check body content if specified
    if [[ -n "$body_contains" ]] && ! grep -qi "$body_contains" "$body" 2>/dev/null; then
      echo "FAIL: ${method} ${url} → body missing '${body_contains}'" >&2
      failures=$((failures + 1))
    fi

    rm -f "$body"
  done <<< "$checks"

  [[ $failures -eq 0 ]]
}

# ── Test: Exec checks from test.yaml ──

@test "${APP}: exec checks pass" {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"

  local checks
  checks=$(yaml_parse_exec_checks "$TEST_YAML")

  [[ -z "$checks" ]] && skip "No exec_checks defined in test.yaml"

  local failures=0

  while IFS='|' read -r container command expected_output; do
    [[ -z "$container" || -z "$command" ]] && continue

    local result
    result=$(compose_cmd "${APP}" exec -T "${container}" sh -c "${command}" 2>/dev/null) || true

    if [[ -n "$expected_output" ]] && ! echo "$result" | grep -qi "$expected_output"; then
      echo "FAIL: exec ${container} '${command}' → output missing '${expected_output}', got: ${result}" >&2
      failures=$((failures + 1))
    fi
  done <<< "$checks"

  [[ $failures -eq 0 ]]
}

# ── Test: Status shows app as running ──

@test "${APP}: status shows running" {
  run "${HOMESTACK_BIN}" status "${APP}"
  assert_success
}

# ── Test: Stop/Start cycle ──

@test "${APP}: stop and start cycle works" {
  run "${HOMESTACK_BIN}" stop "${APP}"
  assert_success

  run "${HOMESTACK_BIN}" start "${APP}"
  assert_success

  # Wait briefly for containers to come back
  sleep 5
}

# ── Test: Backup succeeds ──

@test "${APP}: backup succeeds" {
  run "${HOMESTACK_BIN}" backup "${APP}"
  assert_success

  # At least one backup file should exist
  local count
  count=$(find "${HOMESTACK_DIR}/Backups" -name "${APP}*" -type f 2>/dev/null | wc -l)
  [[ "$count" -gt 0 ]]
}

# ── Test: Remove ──

@test "${APP}: remove succeeds" {
  echo "n" | run "${HOMESTACK_BIN}" remove "${APP}"
  assert_success
}
