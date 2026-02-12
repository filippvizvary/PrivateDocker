#!/usr/bin/env bats
# Unit tests for lib/core.sh (non-Docker functions only)

load '../test_helper'

setup() {
  setup_test_env
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
}

teardown() {
  teardown_test_env
}

# --- validate_path_component ---

@test "validate_path_component: accepts simple name" {
  run validate_path_component "myapp"
  assert_success
}

@test "validate_path_component: accepts name with numbers" {
  run validate_path_component "n8n"
  assert_success
}

@test "validate_path_component: accepts name with hyphens" {
  run validate_path_component "uptime-kuma"
  assert_success
}

@test "validate_path_component: rejects path traversal .." {
  run validate_path_component "../etc"
  assert_failure
}

@test "validate_path_component: rejects embedded .." {
  run validate_path_component "foo/../bar"
  assert_failure
}

@test "validate_path_component: rejects absolute path" {
  run validate_path_component "/root"
  assert_failure
}

# --- ensure_dir ---

@test "ensure_dir: creates missing directory" {
  local target="${TEST_TMPDIR}/newdir/subdir"
  [[ ! -d "$target" ]]
  ensure_dir "$target"
  [[ -d "$target" ]]
}

@test "ensure_dir: succeeds if directory already exists" {
  local target="${TEST_TMPDIR}/existing"
  mkdir -p "$target"
  run ensure_dir "$target"
  assert_success
}

# --- is_installed ---

@test "is_installed: returns false when app not installed" {
  run is_installed "nonexistent"
  assert_failure
}

@test "is_installed: returns true when app dir and app.yaml exist" {
  mkdir -p "${INSTALLED_DIR}/testapp"
  echo "name: testapp" > "${INSTALLED_DIR}/testapp/app.yaml"
  run is_installed "testapp"
  assert_success
}

@test "is_installed: returns false when dir exists but no app.yaml" {
  mkdir -p "${INSTALLED_DIR}/testapp"
  run is_installed "testapp"
  assert_failure
}

# --- get_installed_apps ---

@test "get_installed_apps: returns empty when no apps installed" {
  run get_installed_apps
  assert_success
  assert_output ""
}

@test "get_installed_apps: returns installed app names" {
  # Create two mock installed apps
  mkdir -p "${INSTALLED_DIR}/appb"
  cat > "${INSTALLED_DIR}/appb/app.yaml" <<'EOF'
name: appb
priority: 70
EOF

  mkdir -p "${INSTALLED_DIR}/appa"
  cat > "${INSTALLED_DIR}/appa/app.yaml" <<'EOF'
name: appa
priority: 30
EOF

  run get_installed_apps
  assert_success
  # Should be sorted by priority: appa (30) before appb (70)
  assert_line --index 0 "appa"
  assert_line --index 1 "appb"
}

@test "get_installed_apps: default priority is 50" {
  mkdir -p "${INSTALLED_DIR}/noprior"
  cat > "${INSTALLED_DIR}/noprior/app.yaml" <<'EOF'
name: noprior
EOF

  mkdir -p "${INSTALLED_DIR}/lowprior"
  cat > "${INSTALLED_DIR}/lowprior/app.yaml" <<'EOF'
name: lowprior
priority: 10
EOF

  run get_installed_apps
  assert_success
  # lowprior (10) should come before noprior (50)
  assert_line --index 0 "lowprior"
  assert_line --index 1 "noprior"
}

# --- acquire_lock / release_lock ---

@test "acquire_lock: succeeds on first call" {
  run acquire_lock
  assert_success
  release_lock
}

@test "acquire_lock: fails when lock is already held" {
  # Hold the lock from a subshell
  (
    exec 9>"$LOCK_FILE"
    flock -n 9
    sleep 5
  ) &
  local bg_pid=$!
  sleep 0.2  # give subshell time to acquire

  run acquire_lock
  assert_failure

  kill "$bg_pid" 2>/dev/null || true
  wait "$bg_pid" 2>/dev/null || true
}

# --- check_port_available ---

@test "check_port_available: returns success for unused port" {
  run check_port_available 59123
  assert_success
}

# --- print_help ---

@test "print_help: outputs usage text" {
  run print_help
  assert_success
  assert_output --partial "Usage: homestack"
  assert_output --partial "install"
  assert_output --partial "remove"
  assert_output --partial "backup"
}
