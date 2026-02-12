#!/bin/bash
# HomeStack — core library
# Shared functions sourced by all commands

# --- Colors ---
BLUE="\e[94m\e[1m"
GREEN="\e[32m\e[1m"
RED="\e[31m\e[1m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

# --- Logging ---
step()    { echo -e "${BLUE}[*] $1...${NC}"; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
error()   { echo -e "${RED}[✗] $1${NC}"; }

# --- Paths ---
INSTALLED_DIR="${HOMESTACK_DIR}/installed"
CONFIG_DIR="${HOMESTACK_DIR}/config"
APPDATA_DIR="${HOMESTACK_DIR}/AppData"
BACKUPS_DIR="${HOMESTACK_DIR}/Backups"
MEDIA_DIR="${HOMESTACK_DIR}/Media"
LOCK_FILE="${HOMESTACK_DIR}/.lock"

# Note: APPS_DIR is defined in registry.sh (points to cached catalog)

# --- Lock file for concurrency protection ---
acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    error "Another homestack process is running. If this is wrong, remove ${LOCK_FILE}"
    exit 1
  fi
}

release_lock() {
  flock -u 9 2>/dev/null || true
  rm -f "$LOCK_FILE" 2>/dev/null || true
}

# --- Docker Compose wrapper ---
compose_cmd() {
  local app_dir="$1"
  shift

  if [[ ! -f "${app_dir}/compose.yaml" ]]; then
    error "compose.yaml not found in ${app_dir}"
    return 1
  fi

  local env_flags=(
    --env-file "${CONFIG_DIR}/homestack.env"
  )
  [[ -f "${app_dir}/config.env" ]] && env_flags+=(--env-file "${app_dir}/config.env")
  [[ -f "${app_dir}/secrets.env" ]] && env_flags+=(--env-file "${app_dir}/secrets.env")

  docker compose -f "${app_dir}/compose.yaml" "${env_flags[@]}" "$@"
}

# --- App discovery ---
get_installed_apps() {
  local apps=()

  for dir in "${INSTALLED_DIR}"/*/; do
    [[ -d "$dir" ]] || continue
    [[ -f "${dir}app.yaml" ]] || continue
    local name priority
    name=$(basename "$dir")
    priority=$(yaml_get "${dir}app.yaml" "priority")
    priority="${priority:-50}"
    apps+=("${priority}:${name}")
  done

  [[ ${#apps[@]} -eq 0 ]] && return 0
  printf '%s\n' "${apps[@]}" | sort -t: -k1 -n | cut -d: -f2
}

# Check if an app is installed
is_installed() {
  [[ -d "${INSTALLED_DIR}/$1" && -f "${INSTALLED_DIR}/$1/app.yaml" ]]
}

# --- Network helpers ---
ensure_network() {
  local network="$1"
  if ! docker network inspect "$network" &>/dev/null; then
    docker network create "$network" &>/dev/null
    success "Created Docker network '${network}'"
  fi
}

# --- Directory helpers ---
ensure_dir() {
  [[ -d "$1" ]] || mkdir -p "$1"
}

# Validate a path component (reject path traversal)
validate_path_component() {
  local path="$1"
  if [[ "$path" == *".."* ]] || [[ "$path" == /* ]]; then
    error "Invalid path component: ${path} (path traversal not allowed)"
    return 1
  fi
  return 0
}

# --- Port helpers ---
check_port_available() {
  local port="$1"
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    return 1
  fi
  return 0
}

# --- Help ---
print_help() {
  echo -e "${BLUE}HomeStack${NC} — Self-hosted Docker management"
  echo ""
  echo "Usage: homestack <command> [options]"
  echo ""
  echo "Commands:"
  echo "  install <app>     Install an app from the catalog"
  echo "  remove  <app>     Stop and remove an installed app"
  echo "  start   [app]     Start all or a specific app"
  echo "  stop    [app]     Stop all or a specific app"
  echo "  restart [app]     Restart all or a specific app"
  echo "  status            Show running containers and health"
  echo "  update  [app]     Update all or a specific app"
  echo "  backup  [app]     Backup all or a specific app's data"
  echo "  restore <app>     Restore an app from a backup"
  echo "  list              List installed apps"
  echo "  search  [query]   Search the app catalog"
  echo "  catalog [update]  Sync app catalog from remote"
  echo "  log     [N]       Show last N audit log entries"
  echo ""
  echo "Examples:"
  echo "  homestack install immich"
  echo "  homestack catalog update"
  echo "  homestack start"
  echo "  homestack backup jellyfin"
  echo "  homestack restore jellyfin"
  echo ""
}
  echo "  homestack stop jellyfin"
  echo "  homestack status"
  echo "  homestack search media"
}
