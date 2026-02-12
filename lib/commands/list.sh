#!/bin/bash
# homestack list

cmd_run() {
  local apps
  apps=$(get_installed_apps 2>/dev/null) || true

  if [[ -z "$apps" ]]; then
    echo "No apps installed."
    echo "  Run 'homestack search' to browse the catalog."
    exit 0
  fi

  echo -e "${BLUE}Installed Apps${NC}"
  echo ""
  printf "  %-18s %-15s %-8s %s\n" "NAME" "CATEGORY" "PORT" "VERSION"
  printf "  %-18s %-15s %-8s %s\n" "----" "--------" "----" "-------"

  while IFS= read -r app; do
    local install_dir="${INSTALLED_DIR}/${app}"
    local app_yaml="${install_dir}/app.yaml"
    local display_name category port version
    display_name=$(yaml_get "$app_yaml" "display_name")
    category=$(yaml_get "$app_yaml" "category")
    port=$(yaml_get "$app_yaml" "port")
    version=$(yaml_get "$app_yaml" "version")
    printf "  %-18s %-15s %-8s %s\n" "$display_name" "$category" "$port" "$version"
  done <<< "$apps"

  echo ""
}
