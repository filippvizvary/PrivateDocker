#!/bin/bash
# ============================================================
# HomeStack Test Helper
# Shared setup/teardown loaded by all BATS test files
# Usage: load '../test_helper'
# ============================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# Load BATS libraries
load "${TESTS_DIR}/.bats/bats-support/load"
load "${TESTS_DIR}/.bats/bats-assert/load"

# Create a temporary HomeStack environment for testing
# Sets up all required directories and a minimal homestack.env
setup_test_env() {
  TEST_TMPDIR="$(mktemp -d)"
  export HOMESTACK_DIR="$TEST_TMPDIR"
  export DB_FILE="${HOMESTACK_DIR}/homestack.db"

  # Create standard directory structure
  mkdir -p "${HOMESTACK_DIR}/installed"
  mkdir -p "${HOMESTACK_DIR}/AppData"
  mkdir -p "${HOMESTACK_DIR}/Backups"
  mkdir -p "${HOMESTACK_DIR}/Media"
  mkdir -p "${HOMESTACK_DIR}/config"
  mkdir -p "${HOMESTACK_DIR}/.cache/homestack-apps/apps"

  # Write minimal homestack.env
  cat > "${HOMESTACK_DIR}/config/homestack.env" <<EOF
HOMESTACK_DIR=${HOMESTACK_DIR}
APPDATA=${HOMESTACK_DIR}/AppData
BACKUPS=${HOMESTACK_DIR}/Backups
MEDIA=${HOMESTACK_DIR}/Media
TZ=UTC
PUID=1000
PGID=1000
DOCKER_USER=1000:1000
HOMESTACK_APPS_REPO=https://github.com/filippvizvary/homestack-apps.git
EOF

  # Update library path vars
  export INSTALLED_DIR="${HOMESTACK_DIR}/installed"
  export CONFIG_DIR="${HOMESTACK_DIR}/config"
  export APPDATA_DIR="${HOMESTACK_DIR}/AppData"
  export BACKUPS_DIR="${HOMESTACK_DIR}/Backups"
  export MEDIA_DIR="${HOMESTACK_DIR}/Media"
  export LOCK_FILE="${HOMESTACK_DIR}/.lock"
  export APPS_CACHE_DIR="${HOMESTACK_DIR}/.cache/homestack-apps"
  export APPS_DIR="${APPS_CACHE_DIR}/apps"
}

# Remove temporary test environment
teardown_test_env() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# Source HomeStack library files (non-Docker functions)
source_libs() {
  source "${PROJECT_DIR}/lib/yaml.sh"
  source "${PROJECT_DIR}/lib/core.sh"
  source "${PROJECT_DIR}/lib/db.sh"
  source "${PROJECT_DIR}/lib/secrets.sh"
  source "${PROJECT_DIR}/lib/registry.sh"
}

# Copy the test fixtures catalog into the temp environment
setup_fixture_catalog() {
  local fixtures_dir="${TESTS_DIR}/fixtures/catalog/apps"
  if [[ -d "$fixtures_dir" ]]; then
    cp -r "$fixtures_dir"/* "${APPS_DIR}/"
  fi
}

# Create a minimal test app in the fixture catalog
# Usage: create_fixture_app <name> [port] [priority]
create_fixture_app() {
  local name="$1"
  local port="${2:-18080}"
  local priority="${3:-50}"
  local app_dir="${APPS_DIR}/${name}"

  mkdir -p "$app_dir"

  cat > "${app_dir}/app.yaml" <<EOF
name: ${name}
display_name: ${name^}
description: Test app ${name}
version: 1.0.0
category: other
port: ${port}
priority: ${priority}
networks: []
appdata_dirs: [${name}]
media_dirs: []
EOF

  cat > "${app_dir}/compose.yaml" <<EOF
name: ${name}
services:
  ${name}:
    image: \${${name^^}_SERVER}
    container_name: ${name}
    ports:
      - ${port}:80
    volumes:
      - \${APPDATA}/${name}:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s
EOF

  cat > "${app_dir}/config.env" <<EOF
${name^^}_SERVER=nginx:1.27-alpine
EOF
}

# Install a fixture app into the installed directory (without Docker)
# Useful for testing commands that operate on already-installed apps
mock_install_app() {
  local name="$1"
  local version="${2:-1.0.0}"
  local app_dir="${INSTALLED_DIR}/${name}"

  mkdir -p "$app_dir"

  # Copy from catalog if available
  if [[ -d "${APPS_DIR}/${name}" ]]; then
    cp "${APPS_DIR}/${name}/app.yaml" "$app_dir/"
    cp "${APPS_DIR}/${name}/compose.yaml" "$app_dir/"
    cp "${APPS_DIR}/${name}/config.env" "$app_dir/"
  fi

  # Create empty secrets.env
  echo "# No secrets" > "${app_dir}/secrets.env"
  chmod 600 "${app_dir}/secrets.env"

  # Create AppData directory
  mkdir -p "${APPDATA_DIR}/${name}"

  # Add DB record
  db_set_installed "$name" "$version"
}
