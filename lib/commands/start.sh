#!/bin/bash
# homestack start [app]

cmd_run() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    # Start single app
    if ! is_installed "$target"; then
      error "'${target}' is not installed."
      exit 1
    fi
    local install_dir="${INSTALLED_DIR}/${target}"
    local display_name
    display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")

    # Ensure required networks
    local networks
    networks=$(yaml_get_array "${install_dir}/app.yaml" "networks")
    if [[ -n "$networks" ]]; then
      while IFS= read -r network; do
        ensure_network "$network"
      done <<< "$networks"
    fi

    step "Starting ${display_name}"
    compose_cmd "$install_dir" up -d
    success "${display_name} started"
  else
    # Start all installed apps in priority order
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed. Run 'homestack search' to find apps."
      exit 0
    fi

    echo -e "${BLUE}Starting all apps...${NC}"
    while IFS= read -r app; do
      local install_dir="${INSTALLED_DIR}/${app}"
      local display_name
      display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")

      local networks
      networks=$(yaml_get_array "${install_dir}/app.yaml" "networks")
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
    success "All apps started"
  fi
}
