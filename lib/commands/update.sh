#!/bin/bash
# homestack update [app]

cmd_run() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    update_app "$target"
  else
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed."
      exit 0
    fi

    echo -e "${BLUE}Updating all apps...${NC}"
    while IFS= read -r app; do
      update_app "$app"
    done <<< "$apps"
    echo ""
    success "All apps updated"
  fi
}

update_app() {
  local app_name="$1"

  if ! is_installed "$app_name"; then
    error "'${app_name}' is not installed."
    return 1
  fi

  local install_dir="${INSTALLED_DIR}/${app_name}"
  local app_yaml="${install_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")

  # Check if a newer version exists in the catalog
  local catalog_dir
  catalog_dir=$(registry_find "$app_name")

  if [[ -n "$catalog_dir" ]]; then
    local installed_ver catalog_ver
    installed_ver=$(yaml_get "${install_dir}/app.yaml" "version")
    catalog_ver=$(yaml_get "${catalog_dir}/app.yaml" "version")

    if [[ "$installed_ver" != "$catalog_ver" ]]; then
      step "Updating ${display_name}: ${installed_ver} → ${catalog_ver}"
      # Update app.yaml and compose.yaml from catalog (preserve secrets & config)
      cp "${catalog_dir}/app.yaml" "$install_dir/"
      cp "${catalog_dir}/compose.yaml" "$install_dir/"
      [[ -f "${catalog_dir}/config.env" ]] && cp "${catalog_dir}/config.env" "$install_dir/"
    fi
  fi

  step "Pulling latest images for ${display_name}"
  compose_cmd "$install_dir" pull 2>/dev/null || true

  step "Recreating ${display_name}"
  compose_cmd "$install_dir" up -d --remove-orphans
  success "${display_name} updated"
}
