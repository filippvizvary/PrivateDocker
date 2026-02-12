#!/bin/bash
# homestack install <app>

cmd_run() {
  local app_name="${1:-}"

  if [[ -z "$app_name" ]]; then
    error "Usage: homestack install <app>"
    echo "  Run 'homestack search' to see available apps."
    exit 1
  fi

  # Check if already installed
  if is_installed "$app_name"; then
    error "'${app_name}' is already installed."
    echo "  Run 'homestack remove ${app_name}' first, or 'homestack update ${app_name}'."
    exit 1
  fi

  # Acquire lock for install
  acquire_lock

  # Find in catalog
  local source_dir
  source_dir=$(registry_find "$app_name")
  if [[ -z "$source_dir" ]]; then
    error "App '${app_name}' not found in catalog."
    echo "  Run 'homestack search' to see available apps."
    release_lock
    exit 1
  fi

  local app_yaml="${source_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")
  local port
  port=$(yaml_get "$app_yaml" "port")
  local version
  version=$(yaml_get "$app_yaml" "version")

  echo -e "${BLUE}Installing ${display_name}...${NC}"
  echo ""

  # Check port availability
  if [[ -n "$port" ]] && ! check_port_available "$port"; then
    warn "Port ${port} is already in use. Installation will continue but the app may fail to start."
    echo -ne "  Continue anyway? [y/N]: "
    read -r continue_choice
    if [[ "${continue_choice,,}" != "y" ]]; then
      release_lock
      exit 0
    fi
  fi

  # Set up rollback on failure (non-local so trap can access them)
  _HS_INSTALL_DIR="${INSTALLED_DIR}/${app_name}"
  _HS_INSTALL_APP="${app_name}"
  INSTALL_COMPLETE=false
  local install_dir="$_HS_INSTALL_DIR"

  cleanup_on_failure() {
    if [[ "${INSTALL_COMPLETE:-false}" != "true" ]]; then
      warn "Installation failed, rolling back..."
      compose_cmd "$_HS_INSTALL_DIR" down 2>/dev/null || true
      rm -rf "$_HS_INSTALL_DIR" 2>/dev/null || true
      db_remove_app "$_HS_INSTALL_APP" 2>/dev/null || true
      db_log_action "install" "$_HS_INSTALL_APP" "Installation failed — rolled back" 1
      release_lock
    fi
  }
  trap cleanup_on_failure EXIT

  # Create installed directory and copy app files
  step "Copying app files"
  mkdir -p "$install_dir"
  cp "${source_dir}/compose.yaml" "$install_dir/"
  cp "${source_dir}/app.yaml" "$install_dir/"
  [[ -f "${source_dir}/config.env" ]] && cp "${source_dir}/config.env" "$install_dir/"
  success "App files copied to installed/${app_name}"

  # Create required Docker networks
  local networks
  networks=$(yaml_get_array "$app_yaml" "networks")
  if [[ -n "$networks" ]]; then
    while IFS= read -r network; do
      ensure_network "$network"
    done <<< "$networks"
  fi

  # Create required AppData directories (with path validation)
  local appdata_dirs
  appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")
  if [[ -n "$appdata_dirs" ]]; then
    while IFS= read -r dir; do
      validate_path_component "$dir" || exit 1
      ensure_dir "${APPDATA_DIR}/${dir}"
    done <<< "$appdata_dirs"
    success "AppData directories created"
  fi

  # Create required Media directories
  local media_dirs
  media_dirs=$(yaml_get_array "$app_yaml" "media_dirs")
  if [[ -n "$media_dirs" ]]; then
    while IFS= read -r dir; do
      validate_path_component "$dir" || exit 1
      ensure_dir "${MEDIA_DIR}/${dir}"
    done <<< "$media_dirs"
    success "Media directories created"
  fi

  # Generate secrets
  generate_secrets_file "$app_yaml" "${install_dir}/secrets.env"

  # Track config defaults in database
  db_track_config_defaults "$app_name" "${install_dir}/config.env"

  # Start the app
  step "Starting ${display_name}"
  if compose_cmd "$install_dir" up -d; then
    INSTALL_COMPLETE=true
    trap - EXIT
    release_lock

    # Record in database
    db_set_installed "$app_name" "$version"
    db_log_action "install" "$app_name" "Installed version ${version}"

    echo ""
    success "${display_name} installed and running on port ${port}"
    echo ""
    echo -e "  Manage with:"
    echo -e "    homestack stop ${app_name}"
    echo -e "    homestack start ${app_name}"
    echo -e "    homestack remove ${app_name}"
    [[ -f "${install_dir}/config.env" ]] && \
      echo -e "  Edit config:  ${install_dir}/config.env"
  else
    error "Failed to start ${display_name}"
    exit 1
  fi
}
