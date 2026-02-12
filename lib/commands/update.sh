#!/bin/bash
# homestack update [app]

cmd_run() {
  local target="${1:-}"

  acquire_lock

  if [[ -n "$target" ]]; then
    update_app "$target"
  else
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed."
      release_lock
      exit 0
    fi

    echo -e "${BLUE}Updating all apps...${NC}"
    while IFS= read -r app; do
      update_app "$app"
    done <<< "$apps"
    echo ""
    success "All apps updated"
  fi

  release_lock
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

      # Auto-backup config before update
      step "Backing up current config"
      local backup_dir="${BACKUPS_DIR}/${app_name}"
      ensure_dir "$backup_dir"
      local config_backup="${backup_dir}/${app_name}_config_preupdate_$(date +%Y%m%d_%H%M%S).tar.gz"
      tar -czf "$config_backup" -C "$install_dir" . 2>/dev/null || true
      local backup_size
      backup_size=$(stat -c%s "$config_backup" 2>/dev/null || echo 0)
      db_record_backup "$app_name" "$config_backup" "$backup_size" "config"
      success "Config backed up before update"

      # Update app.yaml and compose.yaml from catalog
      cp "${catalog_dir}/app.yaml" "$install_dir/"
      cp "${catalog_dir}/compose.yaml" "$install_dir/"

      # Smart config merge: preserve user-modified values
      if [[ -f "${catalog_dir}/config.env" ]]; then
        merge_config "$app_name" "$install_dir" "${catalog_dir}/config.env"
      fi

      # Handle new secrets added in the catalog version
      if [[ -f "${install_dir}/secrets.env" ]]; then
        append_new_secrets "${install_dir}/app.yaml" "${install_dir}/secrets.env"
      fi

      # Update DB
      db_set_updated "$app_name" "$catalog_ver"
      # Re-track config defaults from the new catalog version
      db_track_config_defaults "$app_name" "${catalog_dir}/config.env"
    fi
  fi

  step "Pulling latest images for ${display_name}"
  compose_cmd "$install_dir" pull 2>/dev/null || true

  step "Recreating ${display_name}"
  if compose_cmd "$install_dir" up -d --remove-orphans; then
    success "${display_name} updated"
    db_log_action "update" "$app_name" "Updated successfully"
  else
    error "Failed to recreate ${display_name}"
    db_log_action "update" "$app_name" "Update failed during recreate" 1
    return 1
  fi
}

# Smart merge: keep user-modified values, add new keys, update defaults
merge_config() {
  local app_name="$1"
  local install_dir="$2"
  local new_config="$3"
  local current_config="${install_dir}/config.env"

  if [[ ! -f "$current_config" ]]; then
    cp "$new_config" "$current_config"
    return 0
  fi

  local merged_file="${install_dir}/config.env.new"
  cp "$new_config" "$merged_file"

  # For each key in the current config, check if user modified it
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    local key="${line%%=*}"
    local current_value="${line#*=}"
    # Remove surrounding quotes
    current_value="${current_value#\"}" ; current_value="${current_value%\"}"

    if db_is_config_modified "$app_name" "$key" "$current_value"; then
      # User modified this value — preserve it in the merged file
      if grep -q "^${key}=" "$merged_file"; then
        sed -i "s|^${key}=.*|${key}=${current_value}|" "$merged_file"
      else
        echo "${key}=${current_value}" >> "$merged_file"
      fi
      warn "Preserved user-modified config: ${key}"
    fi
  done < "$current_config"

  mv "$merged_file" "$current_config"
}
