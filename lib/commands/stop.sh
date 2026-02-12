#!/bin/bash
# homestack stop [app]

cmd_run() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    # Stop single app
    if ! is_installed "$target"; then
      error "'${target}' is not installed."
      exit 1
    fi
    local install_dir="${INSTALLED_DIR}/${target}"
    local display_name
    display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")
    step "Stopping ${display_name}"
    compose_cmd "$install_dir" down
    success "${display_name} stopped"
  else
    # Stop all installed apps in reverse priority order
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed."
      exit 0
    fi

    # Reverse the list
    local reversed
    reversed=$(echo "$apps" | tac)

    echo -e "${BLUE}Stopping all apps...${NC}"
    while IFS= read -r app; do
      local install_dir="${INSTALLED_DIR}/${app}"
      local display_name
      display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")
      step "Stopping ${display_name}"
      compose_cmd "$install_dir" down 2>/dev/null || true
      success "${display_name} stopped"
    done <<< "$reversed"

    echo ""
    success "All apps stopped"
  fi
}
