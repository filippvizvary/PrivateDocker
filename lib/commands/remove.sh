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

  local install_dir="${INSTALLED_DIR}/${app_name}"
  local app_yaml="${install_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")

  echo -e "${BLUE}Removing ${display_name}...${NC}"

  # Stop the app
  step "Stopping containers"
  compose_cmd "$install_dir" down 2>/dev/null || true
  success "Containers stopped"

  # Ask about AppData
  local appdata_dirs
  appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")
  if [[ -n "$appdata_dirs" ]]; then
    echo ""
    echo -ne "  Delete app data in AppData/? ${RED}This cannot be undone.${NC} [y/N]: "
    read -r delete_data
    if [[ "${delete_data,,}" == "y" ]]; then
      while IFS= read -r dir; do
        rm -rf "${APPDATA_DIR:?}/${dir}"
      done <<< "$appdata_dirs"
      success "AppData deleted"
    else
      success "AppData preserved in ${APPDATA_DIR}/"
    fi
  fi

  # Remove installed files
  rm -rf "$install_dir"
  success "${display_name} removed"
}
