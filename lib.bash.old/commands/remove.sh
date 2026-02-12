#!/bin/bash
# homestack remove <app>

cmd_run() {
  local app_name="${1:-}"

  if [[ -z "$app_name" ]]; then
    error "Usage: homestack remove <app>"
    exit 1
  fi

  if ! is_installed "$app_name"; then
    error "'${app_name}' is not installed."
    exit 1
  fi

  acquire_lock

  local install_dir="${INSTALLED_DIR}/${app_name}"
  local app_yaml="${install_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")

  echo -e "${BLUE}Removing ${display_name}...${NC}"

  # Stop containers
  step "Stopping containers"
  if ! compose_cmd "$install_dir" down 2>/dev/null; then
    warn "Some containers may not have stopped cleanly"
  fi
  success "Containers stopped"

  # Clean up Docker networks specific to this app
  local networks
  networks=$(yaml_get_array "$app_yaml" "networks")
  if [[ -n "$networks" ]]; then
    while IFS= read -r network; do
      # Only remove if no other containers use the network
      local connected
      connected=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
      if [[ "$connected" == "0" ]]; then
        docker network rm "$network" 2>/dev/null && \
          success "Removed Docker network '${network}'" || true
      fi
    done <<< "$networks"
  fi

  # Ask about AppData
  local appdata_dirs
  appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")
  if [[ -n "$appdata_dirs" ]]; then
    echo ""
    echo -ne "  Delete app data in AppData/? ${RED}This cannot be undone.${NC} [y/N]: "
    read -r delete_data
    if [[ "${delete_data,,}" == "y" ]]; then
      while IFS= read -r dir; do
        validate_path_component "$dir" || continue
        rm -rf "${APPDATA_DIR:?}/${dir}"
      done <<< "$appdata_dirs"
      success "AppData deleted"
    else
      success "AppData preserved in ${APPDATA_DIR}/"
    fi
  fi

  # Remove installed files
  rm -rf "$install_dir"

  # Remove from database
  db_remove_app "$app_name"
  db_log_action "remove" "$app_name" "Removed ${display_name}"

  release_lock
  success "${display_name} removed"
}
