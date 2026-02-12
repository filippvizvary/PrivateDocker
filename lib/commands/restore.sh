#!/bin/bash
# homestack restore <app>

cmd_run() {
  local app_name="${1:-}"

  if [[ -z "$app_name" ]]; then
    error "Usage: homestack restore <app>"
    exit 1
  fi

  if ! is_installed "$app_name"; then
    error "'${app_name}' is not installed."
    echo "  Install it first with: homestack install ${app_name}"
    exit 1
  fi

  acquire_lock

  local install_dir="${INSTALLED_DIR}/${app_name}"
  local app_yaml="${install_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")

  echo -e "${BLUE}Restore ${display_name}${NC}"
  echo ""

  # List available backups from database
  local backups
  backups=$(db_list_backups "$app_name")

  if [[ -z "$backups" ]]; then
    # Fallback: check filesystem
    local backup_dir="${BACKUPS_DIR}/${app_name}"
    if [[ ! -d "$backup_dir" ]] || ! ls "$backup_dir"/*.tar.gz &>/dev/null; then
      error "No backups found for ${app_name}"
      release_lock
      exit 1
    fi
    warn "No backup records in database. Listing files from ${backup_dir}:"
    echo ""
    local i=1
    local files=()
    while IFS= read -r f; do
      files+=("$f")
      local size
      size=$(du -h "$f" 2>/dev/null | cut -f1)
      echo -e "  ${CYAN}${i})${NC} $(basename "$f") (${size})"
      ((i++))
    done < <(ls -t "$backup_dir"/*.tar.gz 2>/dev/null)

    echo ""
    echo -ne "  Select backup number [1]: "
    read -r choice
    choice="${choice:-1}"

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#files[@]} ]]; then
      error "Invalid selection"
      release_lock
      exit 1
    fi

    local selected_file="${files[$((choice - 1))]}"
    restore_from_file "$app_name" "$selected_file" "$install_dir" "$app_yaml" "$display_name"
  else
    # Show backups from DB
    echo -e "  Available backups:"
    echo ""
    printf "  %-4s %-12s %-40s %-10s %s\n" "#" "TYPE" "FILE" "SIZE" "DATE"
    printf "  %-4s %-12s %-40s %-10s %s\n" "---" "----" "----" "----" "----"

    local i=1
    local ids=()
    local paths=()
    local types=()
    while IFS='|' read -r bid bpath bsize bdate btype; do
      ids+=("$bid")
      paths+=("$bpath")
      types+=("$btype")
      local human_size
      human_size=$(numfmt --to=iec "$bsize" 2>/dev/null || echo "${bsize}B")
      printf "  %-4s %-12s %-40s %-10s %s\n" "$i" "$btype" "$(basename "$bpath")" "$human_size" "$bdate"
      ((i++))
    done <<< "$backups"

    echo ""
    echo -ne "  Select backup number [1]: "
    read -r choice
    choice="${choice:-1}"

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -ge $i ]]; then
      error "Invalid selection"
      release_lock
      exit 1
    fi

    local idx=$((choice - 1))
    local selected_path="${paths[$idx]}"
    local selected_type="${types[$idx]}"

    if [[ ! -f "$selected_path" ]]; then
      error "Backup file not found: ${selected_path}"
      release_lock
      exit 1
    fi

    restore_from_file "$app_name" "$selected_path" "$install_dir" "$app_yaml" "$display_name" "$selected_type"
  fi

  release_lock
}

restore_from_file() {
  local app_name="$1"
  local archive="$2"
  local install_dir="$3"
  local app_yaml="$4"
  local display_name="$5"
  local backup_type="${6:-}"

  echo ""
  echo -ne "  ${YELLOW}This will overwrite current data. Continue?${NC} [y/N]: "
  read -r confirm
  if [[ "${confirm,,}" != "y" ]]; then
    echo "  Restore cancelled."
    return 0
  fi

  # Stop the app
  step "Stopping ${display_name}"
  compose_cmd "$install_dir" down 2>/dev/null || true

  # Determine where to restore based on type
  if [[ "$backup_type" == "config" ]]; then
    step "Restoring config for ${display_name}"
    tar -xzf "$archive" -C "$install_dir"
    success "Config restored"
  elif [[ "$backup_type" == "data" ]]; then
    step "Restoring data for ${display_name}"
    tar -xzf "$archive" -C "${APPDATA_DIR}"
    success "Data restored"
  else
    # Unknown type — guess from filename
    local basename_archive
    basename_archive=$(basename "$archive")
    if [[ "$basename_archive" == *"_config_"* ]]; then
      step "Restoring config for ${display_name}"
      tar -xzf "$archive" -C "$install_dir"
      success "Config restored"
    elif [[ "$basename_archive" == *"_data_"* ]]; then
      step "Restoring data for ${display_name}"
      tar -xzf "$archive" -C "${APPDATA_DIR}"
      success "Data restored"
    else
      # Legacy format — restore to AppData
      local appdata_dirs
      appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")
      if [[ -n "$appdata_dirs" ]]; then
        local first_dir
        first_dir=$(echo "$appdata_dirs" | head -1)
        step "Restoring data for ${display_name}"
        tar -xzf "$archive" -C "${APPDATA_DIR}/${first_dir}"
        success "Data restored to AppData/${first_dir}"
      fi
    fi
  fi

  # Restart the app
  local networks
  networks=$(yaml_get_array "$app_yaml" "networks")
  if [[ -n "$networks" ]]; then
    while IFS= read -r network; do
      ensure_network "$network"
    done <<< "$networks"
  fi

  step "Starting ${display_name}"
  compose_cmd "$install_dir" up -d
  success "${display_name} restored and running"

  db_log_action "restore" "$app_name" "Restored from $(basename "$archive")"
}
