#!/bin/bash
# HomeStack — App registry / catalog
# Fetches and discovers apps from the homestack-apps repository

APPS_CACHE_DIR="${HOMESTACK_DIR}/.cache/homestack-apps"
APPS_REPO_URL="${HOMESTACK_APPS_REPO:-https://github.com/filippvizvary/homestack-apps.git}"
APPS_DIR="${APPS_CACHE_DIR}/apps"

# Sync app catalog from remote repository
registry_sync() {
  # Ensure git trusts the cache directory (owned by homestack user, run by group member)
  git config --global --add safe.directory "$APPS_CACHE_DIR" 2>/dev/null || true

  if [[ -d "${APPS_CACHE_DIR}/.git" ]]; then
    step "Updating app catalog"
    if git -C "$APPS_CACHE_DIR" pull --quiet 2>/dev/null; then
      success "App catalog updated"
    else
      warn "Failed to update catalog, using cached version"
      return 1
    fi
  else
    step "Downloading app catalog"
    mkdir -p "$(dirname "$APPS_CACHE_DIR")"
    if git clone --depth 1 "$APPS_REPO_URL" "$APPS_CACHE_DIR" 2>/dev/null; then
      success "App catalog downloaded"
    else
      error "Failed to download app catalog from ${APPS_REPO_URL}"
      return 1
    fi
  fi

  # Update catalog versions in database
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    for dir in "${APPS_DIR}"/*/; do
      [[ -f "${dir}app.yaml" ]] || continue
      local name version
      name=$(basename "$dir")
      version=$(yaml_get "${dir}app.yaml" "version")
      if db_is_installed "$name"; then
        db_set_catalog_version "$name" "$version"
      fi
    done
  fi
}

# Ensure catalog is available, sync if missing
registry_ensure() {
  if [[ ! -d "$APPS_DIR" ]]; then
    registry_sync || return 1
  fi
}

# List all available apps from the catalog
# Returns: name|display_name|description|category|port
registry_list() {
  registry_ensure || return 1
  for dir in "${APPS_DIR}"/*/; do
    [[ -f "${dir}app.yaml" ]] || continue
    local name display category port description
    name=$(yaml_get "${dir}app.yaml" "name")
    display=$(yaml_get "${dir}app.yaml" "display_name")
    description=$(yaml_get "${dir}app.yaml" "description")
    category=$(yaml_get "${dir}app.yaml" "category")
    port=$(yaml_get "${dir}app.yaml" "port")
    echo "${name}|${display}|${description}|${category}|${port}"
  done
}

# Find an app by exact name in the catalog
# Returns the app directory path, or empty if not found
registry_find() {
  local app_name="$1"
  registry_ensure || return 1
  local app_dir="${APPS_DIR}/${app_name}"
  if [[ -d "$app_dir" && -f "${app_dir}/app.yaml" ]]; then
    echo "$app_dir"
  fi
}

# Search apps by query (matches name, display_name, description, category)
registry_search() {
  local query="$1"
  registry_ensure || return 1
  local query_lower
  query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

  for dir in "${APPS_DIR}"/*/; do
    [[ -f "${dir}app.yaml" ]] || continue
    local name display description category port
    name=$(yaml_get "${dir}app.yaml" "name")
    display=$(yaml_get "${dir}app.yaml" "display_name")
    description=$(yaml_get "${dir}app.yaml" "description")
    category=$(yaml_get "${dir}app.yaml" "category")
    port=$(yaml_get "${dir}app.yaml" "port")

    local haystack
    haystack=$(echo "${name} ${display} ${description} ${category}" | tr '[:upper:]' '[:lower:]')

    if [[ "$haystack" == *"$query_lower"* ]]; then
      echo "${name}|${display}|${description}|${category}|${port}"
    fi
  done
}
