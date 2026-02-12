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

  local appdata_dirs
  appdata_dirs=$(yaml_get_array "$app_yaml" "appdata_dirs")

  if [[ -z "$appdata_dirs" ]]; then
    warn "${display_name}: no AppData directories defined, skipping"
    return 0
  fi

  while IFS= read -r dir; do
    local src="${APPDATA_DIR}/${dir}"
    if [[ ! -d "$src" ]]; then
      warn "${display_name}: ${src} does not exist, skipping"
      continue
    fi

    local dest="${BACKUPS_DIR}/${app_name}"
    ensure_dir "$dest"

    local archive="${dest}/${app_name}_${timestamp}.tar.gz"
    step "Backing up ${display_name} (${dir})"
    tar -czf "$archive" -C "$src" .

    # Rotate: keep only the last N backups
    ls -t "${dest}"/*.tar.gz 2>/dev/null | tail -n +$((KEEP_LAST + 1)) | xargs -r rm --
    success "${display_name} → $(basename "$archive")"
  done <<< "$appdata_dirs"
}
