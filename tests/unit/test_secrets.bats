#!/usr/bin/env bats
# Unit tests for lib/secrets.sh

load '../test_helper'

setup() {
  setup_test_env
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  source "${PROJECT_DIR}/lib/secrets.sh"
}

teardown() {
  teardown_test_env
}

# --- generate_password ---

@test "generate_password: default length is 32" {
  run generate_password
  assert_success
  [ "${#output}" -eq 32 ]
}

@test "generate_password: respects custom length" {
  run generate_password 16
  assert_success
  [ "${#output}" -eq 16 ]
}

@test "generate_password: short length works" {
  run generate_password 8
  assert_success
  [ "${#output}" -eq 8 ]
}

@test "generate_password: long length works" {
  run generate_password 64
  assert_success
  [ "${#output}" -eq 64 ]
}

@test "generate_password: output is alphanumeric only" {
  local pw
  pw=$(generate_password 100)
  # Should match only [A-Za-z0-9]
  [[ "$pw" =~ ^[A-Za-z0-9]+$ ]]
}

@test "generate_password: successive calls produce different output" {
  local pw1 pw2
  pw1=$(generate_password 32)
  pw2=$(generate_password 32)
  [[ "$pw1" != "$pw2" ]]
}

# --- generate_secrets_file ---

@test "generate_secrets_file: creates secrets.env from app with secrets" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local output_file="${TEST_TMPDIR}/secrets.env"

  # generate_secrets_file uses generate_password for 'generate: true' keys
  # but also prompts for non-generate keys. Our testapp only has generate: true.
  run generate_secrets_file "$app_yaml" "$output_file"
  assert_success

  # File should exist
  [[ -f "$output_file" ]]

  # Should contain TEST_SECRET key
  grep -q "^TEST_SECRET=" "$output_file"
}

@test "generate_secrets_file: sets restrictive permissions" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local output_file="${TEST_TMPDIR}/secrets.env"

  generate_secrets_file "$app_yaml" "$output_file"

  # Check permissions (600 = owner r/w only)
  local perms
  perms=$(stat -c %a "$output_file")
  [[ "$perms" == "600" ]]
}

@test "generate_secrets_file: handles app with no secrets" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp-nosecrets/app.yaml"
  local output_file="${TEST_TMPDIR}/secrets.env"

  run generate_secrets_file "$app_yaml" "$output_file"
  assert_success

  # File should exist with comment header
  [[ -f "$output_file" ]]
  grep -q "No secrets" "$output_file"
}

@test "generate_secrets_file: generated password has correct length" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local output_file="${TEST_TMPDIR}/secrets.env"

  generate_secrets_file "$app_yaml" "$output_file"

  # Extract the value (TEST_SECRET has length 16 in fixture)
  local value
  value=$(grep "^TEST_SECRET=" "$output_file" | cut -d= -f2- | tr -d '"')
  [ "${#value}" -eq 16 ]
}

# --- append_new_secrets ---

@test "append_new_secrets: adds missing keys to existing secrets file" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local secrets_file="${TEST_TMPDIR}/secrets.env"

  # Create initial empty secrets file
  echo "# Initial secrets" > "$secrets_file"

  run append_new_secrets "$app_yaml" "$secrets_file"
  assert_success

  # TEST_SECRET should now be in the file
  grep -q "^TEST_SECRET=" "$secrets_file"
}

@test "append_new_secrets: does not overwrite existing keys" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local secrets_file="${TEST_TMPDIR}/secrets.env"

  # Create secrets file with existing value
  echo 'TEST_SECRET="original_value"' > "$secrets_file"

  run append_new_secrets "$app_yaml" "$secrets_file"
  assert_success

  # Original value should be preserved
  grep -q 'TEST_SECRET="original_value"' "$secrets_file"
}

@test "append_new_secrets: no-op when all keys already exist" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp/app.yaml"
  local secrets_file="${TEST_TMPDIR}/secrets.env"

  echo 'TEST_SECRET="existing"' > "$secrets_file"
  local before_size
  before_size=$(wc -c < "$secrets_file")

  run append_new_secrets "$app_yaml" "$secrets_file"
  assert_success

  # File should not grow
  local after_size
  after_size=$(wc -c < "$secrets_file")
  [[ "$before_size" -eq "$after_size" ]]
}

@test "append_new_secrets: no-op for app with no secrets" {
  local app_yaml="${TESTS_DIR}/fixtures/catalog/apps/testapp-nosecrets/app.yaml"
  local secrets_file="${TEST_TMPDIR}/secrets.env"

  echo "# Existing" > "$secrets_file"

  run append_new_secrets "$app_yaml" "$secrets_file"
  assert_success
}
