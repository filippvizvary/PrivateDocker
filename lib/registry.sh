#!/bin/bash
# HomeStack — App registry / catalog
# Discovers available apps from the local apps/ directory
# Future: also fetch from remote homestack-apps repo

# List all available apps from the catalog
# Returns: name|display_name|description|category|port
registry_list() {
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
  local app_dir="${APPS_DIR}/${app_name}"
  if [[ -d "$app_dir" && -f "${app_dir}/app.yaml" ]]; then
    echo "$app_dir"
  fi
}

# Search apps by query (matches name, display_name, description, category)
# Usage: registry_search <query>
registry_search() {
  local query="$1"
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

# Sync app catalog from remote repository (future)
# registry_sync() {
#   local remote_repo="https://github.com/filippvizvary/homestack-apps.git"
#   local cache_dir="${HOMESTACK_DIR}/.cache/app-store"
#   if [[ -d "$cache_dir" ]]; then
#     git -C "$cache_dir" pull --quiet
#   else
#     git clone --depth 1 "$remote_repo" "$cache_dir"
#   fi
#   # Merge remote apps into local apps/ dir
# }
