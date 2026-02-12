#!/bin/bash
# homestack backup [app]

KEEP_LAST=5

cmd_run() {
  local target="${1:-}"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)

  echo -e "${BLUE}=== HomeStack Backup — $(date) ===${NC}"
  echo ""

  if [[ -n "$target" ]]; then
    backup_app "$target" "$timestamp"
  else
    local apps
    apps=$(get_installed_apps)
    if [[ -z "$apps" ]]; then
      warn "No apps installed."
      exit 0
    fi
    while IFS= read -r app; do
      backup_app "$app" "$timestamp"
    done <<< "$apps"
  fi

  echo ""
  success "Backup complete"
}

backup_app() {
  local app_name="$1"
  local timestamp="$2"

  if ! is_installed "$app_name"; then
    error "'${app_name}' is not installed."
    return 1
  fi

  local install_dir="${INSTALLED_DIR}/${app_name}"
  local app_yaml="${install_dir}/app.yaml"
  local display_name
  display_name=$(yaml_get "$app_yaml" "display_name")

  local dest="${BACKUPS_DIR}/${app_name}"
  ensure_dir "$dest"

  # Backup config files (secrets.env, config.env, app.yaml, compose.yaml)
  step "Backing up ${display_name} config"
  local config_archive="${dest}/${app_name}_config_${timestamp}.tar.gz"
  tar -czf "$config_archive" -C "$install_dir" . 2>/dev/null || true
  local config_size
  config_size=$(stat -c%s "$config_archive" 2>/dev/null || echo 0)
  db_record_backup "$app_name" "$config_archive" "$config_size" "config"
  success "${display_name} config → $(basename "$config_archive")"

  # Backup AppData
  local appdata_dirs
  appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")

  if [[ -z "$appdata_dirs" ]]; then
    warn "${display_name}: no AppData directories defined, skipping data backup"
    db_log_action "backup" "$app_name" "Config backup only (no appdata)" 0
    return 0
  fi

  # Check backup strategy from app.yaml
  local backup_strategy
  backup_strategy=$(yaml_get "$app_yaml" "backup_strategy")
  backup_strategy="${backup_strategy:-stop}"

  local was_running=false
  if [[ "$backup_strategy" == "stop" ]]; then
    # Check if containers are running
    if compose_cmd "$install_dir" ps --quiet 2>/dev/null | grep -q .; then
      was_running=true
      step "Stopping ${display_name} for safe backup"
      compose_cmd "$install_dir" down 2>/dev/null || true
    fi
  fi

  # Archive all appdata dirs into a single archive
  local data_archive="${dest}/${app_name}_data_${timestamp}.tar.gz"
  local tar_args=()
  local has_data=false

  while IFS= read -r dir; do
    validate_path_component "$dir" || continue
    local src="${APPDATA_DIR}/${dir}"
    if [[ -d "$src" ]]; then
      tar_args+=(-C "${APPDATA_DIR}" "$dir")
      has_data=true
    else
      warn "${display_name}: ${src} does not exist, skipping"
    fi
  done <<< "$appdata_dirs"

  if $has_data; then
    step "Backing up ${display_name} data"
    tar -czf "$data_archive" "${tar_args[@]}"
    local data_size
    data_size=$(stat -c%s "$data_archive" 2>/dev/null || echo 0)
    db_record_backup "$app_name" "$data_archive" "$data_size" "data"
    success "${display_name} data → $(basename "$data_archive")"
  fi

  # Restart if we stopped it
  if $was_running; then
    step "Restarting ${display_name}"
    # Ensure networks exist
    local networks
    networks=$(yaml_get_array "$app_yaml" "networks")
    if [[ -n "$networks" ]]; then
      while IFS= read -r network; do
        ensure_network "$network"
      done <<< "$networks"
    fi
    compose_cmd "$install_dir" up -d
    success "${display_name} restarted"
  fi

  # Rotate: keep only the last N data backups
  ls -t "${dest}"/${app_name}_data_*.tar.gz 2>/dev/null | tail -n +$((KEEP_LAST + 1)) | xargs -r rm --
  ls -t "${dest}"/${app_name}_config_*.tar.gz 2>/dev/null | tail -n +$((KEEP_LAST + 1)) | xargs -r rm --

  db_log_action "backup" "$app_name" "Backup completed: config + data" 0
}
