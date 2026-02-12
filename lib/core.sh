#!/bin/bash
# HomeStack — core library
# Shared functions sourced by all commands

# --- Colors ---
BLUE="\e[94m\e[1m"
GREEN="\e[32m\e[1m"
RED="\e[31m\e[1m"
YELLOW="\e[33m"
NC="\e[0m"

# --- Logging ---
step()    { echo -e "${BLUE}[*] $1...${NC}"; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
error()   { echo -e "${RED}[✗] $1${NC}"; }

# --- Paths ---
INSTALLED_DIR="${HOMESTACK_DIR}/installed"
APPS_DIR="${HOMESTACK_DIR}/apps"
CONFIG_DIR="${HOMESTACK_DIR}/config"
APPDATA_DIR="${HOMESTACK_DIR}/AppData"
BACKUPS_DIR="${HOMESTACK_DIR}/Backups"
MEDIA_DIR="${HOMESTACK_DIR}/Media"

# --- Docker Compose wrapper ---
# Loads global config + per-app config + per-app secrets, then runs compose
compose_cmd() {
  local app_dir="$1"
  shift

  local env_flags=(
    --env-file "${CONFIG_DIR}/homestack.env"
  )
  [[ -f "${app_dir}/config.env" ]] && env_flags+=(--env-file "${app_dir}/config.env")
  [[ -f "${app_dir}/secrets.env" ]] && env_flags+=(--env-file "${app_dir}/secrets.env")

  docker compose -f "${app_dir}/compose.yaml" "${env_flags[@]}" "$@"
}

# --- App discovery ---
# List all installed app names (sorted by priority)
get_installed_apps() {
  local apps=()
  local priorities=()

  for dir in "${INSTALLED_DIR}"/*/; do
    [[ -f "${dir}app.yaml" ]] || continue
    local name
    name=$(basename "$dir")
    local priority
    priority=$(yaml_get "${dir}app.yaml" "priority")
    priority="${priority:-50}"
    apps+=("${priority}:${name}")
  done

  # Sort by priority (numeric) and return just names
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
  echo "  list              List installed apps"
  echo "  search  [query]   Search the app catalog"
  echo ""
  echo "Examples:"
  echo "  homestack install immich"
  echo "  homestack start"
  echo "  homestack stop jellyfin"
  echo "  homestack status"
  echo "  homestack search media"
}
