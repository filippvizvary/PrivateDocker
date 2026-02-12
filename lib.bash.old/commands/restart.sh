#!/bin/bash
# homestack restart [app]

cmd_run() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    if ! is_installed "$target"; then
      error "'${target}' is not installed."
      exit 1
    fi
    local install_dir="${INSTALLED_DIR}/${target}"
    local app_yaml="${install_dir}/app.yaml"
    local display_name
    display_name=$(yaml_get "$app_yaml" "display_name")
    step "Restarting ${display_name}"
    compose_cmd "$install_dir" down 2>/dev/null || true

    # Ensure networks before restart
    local networks
    networks=$(yaml_get_array "$app_yaml" "networks")
    if [[ -n "$networks" ]]; then
      while IFS= read -r network; do
        ensure_network "$network"
      done <<< "$networks"
    fi

    compose_cmd "$install_dir" up -d
    success "${display_name} restarted"
    db_log_action "restart" "$target" "Restarted"
  else
    # Restart all: stop in reverse priority, then start in priority order
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed."
      exit 0
    fi

    echo -e "${BLUE}Restarting all apps...${NC}"

    # Stop all in reverse order
    local reversed
    reversed=$(echo "$apps" | tac)
    while IFS= read -r app; do
      local install_dir="${INSTALLED_DIR}/${app}"
      local display_name
      display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")
      step "Stopping ${display_name}"
      compose_cmd "$install_dir" down 2>/dev/null || true
      success "${display_name} stopped"
    done <<< "$reversed"

    # Start all in priority order
    while IFS= read -r app; do
      local install_dir="${INSTALLED_DIR}/${app}"
      local app_yaml="${install_dir}/app.yaml"
      local display_name
      display_name=$(yaml_get "$app_yaml" "display_name")

      local networks
      networks=$(yaml_get_array "$app_yaml" "networks")
      if [[ -n "$networks" ]]; then
        while IFS= read -r network; do
          ensure_network "$network"
        done <<< "$networks"
      fi

      step "Starting ${display_name}"
      compose_cmd "$install_dir" up -d
      success "${display_name} started"
    done <<< "$apps"

    echo ""
    success "All apps restarted"
    db_log_action "restart" "" "Restarted all apps"
  fi
}
