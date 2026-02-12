#!/usr/bin/env bats
# Unit tests for lib/registry.sh (filesystem-only, no git)

load '../test_helper'

setup() {
  setup_test_env
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  source "${PROJECT_DIR}/lib/registry.sh"

  # Point APPS_DIR at our fixtures instead of needing git
  export APPS_DIR="${TESTS_DIR}/fixtures/catalog/apps"
}

teardown() {
  teardown_test_env
}

# --- registry_find ---

@test "registry_find: returns path for existing app" {
  run registry_find "testapp"
  assert_success
  [[ "$output" == *"testapp"* ]]
  [[ -d "$output" ]]
}

@test "registry_find: returns empty for nonexistent app" {
  run registry_find "nonexistent"
  assert_success
  assert_output ""
}

@test "registry_find: returns path for testapp-nosecrets" {
  run registry_find "testapp-nosecrets"
  assert_success
  [[ "$output" == *"testapp-nosecrets"* ]]
}

# --- registry_list ---

@test "registry_list: returns all fixture apps" {
  run registry_list
  assert_success
  [[ "$output" == *"testapp|"* ]]
  [[ "$output" == *"testapp-nosecrets|"* ]]
}

@test "registry_list: output format is pipe-delimited (name|display|desc|cat|port)" {
  run registry_list
  assert_success
  local first_line
  first_line=$(echo "$output" | head -1)
  # Count pipes — should have 4 (5 fields)
  local pipe_count
  pipe_count=$(echo "$first_line" | tr -cd '|' | wc -c)
  [[ "$pipe_count" -eq 4 ]]
}

# --- registry_search ---

@test "registry_search: finds app by name" {
  run registry_search "testapp"
  assert_success
  [[ "$output" == *"testapp"* ]]
}

@test "registry_search: case-insensitive search" {
  run registry_search "TESTAPP"
  assert_success
  [[ "$output" == *"testapp"* ]]
}

@test "registry_search: finds app by description" {
  run registry_search "integration"
  assert_success
  [[ "$output" == *"testapp"* ]]
}

@test "registry_search: returns empty for no matches" {
  run registry_search "zzz_nonexistent_zzz"
  assert_success
  assert_output ""
}

@test "registry_search: finds app by category" {
  run registry_search "other"
  assert_success
  [[ "$output" == *"testapp"* ]]
}
