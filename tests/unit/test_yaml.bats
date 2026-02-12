#!/usr/bin/env bats
# Unit tests for lib/yaml.sh

load '../test_helper'

setup() {
  setup_test_env
  source "${PROJECT_DIR}/lib/yaml.sh"
}

teardown() {
  teardown_test_env
}

# --- yaml_get ---

@test "yaml_get: retrieves scalar string value" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "name"
  assert_success
  assert_output "testapp"
}

@test "yaml_get: retrieves display_name with spaces" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "display_name"
  assert_success
  assert_output "Test App"
}

@test "yaml_get: retrieves integer value (port)" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "port"
  assert_success
  assert_output "18080"
}

@test "yaml_get: retrieves integer value (priority)" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "priority"
  assert_success
  assert_output "50"
}

@test "yaml_get: retrieves URL value" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "url"
  assert_success
  assert_output "https://example.com"
}

@test "yaml_get: returns empty for missing key" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "nonexistent_key"
  assert_success
  assert_output ""
}

@test "yaml_get: retrieves backup_strategy" {
  run yaml_get "${TESTS_DIR}/fixtures/sample.yaml" "backup_strategy"
  assert_success
  assert_output "stop"
}

# --- yaml_get_array ---

@test "yaml_get_array: parses inline array with two items" {
  run yaml_get_array "${TESTS_DIR}/fixtures/sample.yaml" "networks"
  assert_success
  assert_line --index 0 "test-net"
  assert_line --index 1 "proxy"
}

@test "yaml_get_array: parses inline array with two appdata_dirs" {
  run yaml_get_array "${TESTS_DIR}/fixtures/sample.yaml" "appdata_dirs"
  assert_success
  assert_line --index 0 "testapp"
  assert_line --index 1 "testapp-db"
}

@test "yaml_get_array: parses media_dirs with multiple entries" {
  run yaml_get_array "${TESTS_DIR}/fixtures/sample.yaml" "media_dirs"
  assert_success
  assert_line --index 0 "Movies"
  assert_line --index 1 "Downloads"
}

@test "yaml_get_array: returns empty for empty array []" {
  run yaml_get_array "${TESTS_DIR}/fixtures/nosecrets.yaml" "networks"
  # grep -v '^$' returns 1 when no lines pass — that's expected
  assert_output ""
}

@test "yaml_get_array: returns empty for missing key" {
  run yaml_get_array "${TESTS_DIR}/fixtures/nosecrets.yaml" "nonexistent"
  assert_output ""
}

# --- yaml_parse_secrets ---

@test "yaml_parse_secrets: parses three secrets correctly" {
  run yaml_parse_secrets "${TESTS_DIR}/fixtures/sample.yaml"
  assert_success
  # Should have 3 lines
  [ "$(echo "$output" | wc -l)" -eq 3 ]
}

@test "yaml_parse_secrets: first secret has generate=true and length=24" {
  run yaml_parse_secrets "${TESTS_DIR}/fixtures/sample.yaml"
  assert_success
  local first_line
  first_line=$(echo "$output" | head -1)
  # Format: key|prompt|default|generate|length
  [[ "$first_line" == "DB_PASSWORD|Database password||true|24" ]]
}

@test "yaml_parse_secrets: second secret has default value" {
  run yaml_parse_secrets "${TESTS_DIR}/fixtures/sample.yaml"
  assert_success
  local second_line
  second_line=$(echo "$output" | sed -n '2p')
  [[ "$second_line" == "DB_USERNAME|Database username|testuser|false|32" ]]
}

@test "yaml_parse_secrets: third secret has length=64" {
  run yaml_parse_secrets "${TESTS_DIR}/fixtures/sample.yaml"
  assert_success
  local third_line
  third_line=$(echo "$output" | sed -n '3p')
  [[ "$third_line" == "API_KEY|External API key||true|64" ]]
}

@test "yaml_parse_secrets: returns empty for file with no secrets" {
  run yaml_parse_secrets "${TESTS_DIR}/fixtures/nosecrets.yaml"
  # No secrets block means no output — exit code may be non-zero
  assert_output ""
}
