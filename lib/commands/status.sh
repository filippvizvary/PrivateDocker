#!/bin/bash
# homestack status

cmd_run() {
  local apps
  apps=$(get_installed_apps 2>/dev/null) || true

  if [[ -z "$apps" ]]; then
    warn "No apps installed."
    exit 0
  fi

  echo -e "${BLUE}HomeStack — Service Status${NC}"
  echo ""

  # Table header
  printf "  %-18s %-12s %-30s %s\n" "APP" "PORT" "STATUS" "CONTAINERS"
  printf "  %-18s %-12s %-30s %s\n" "---" "----" "------" "----------"

  while IFS= read -r app; do
    local install_dir="${INSTALLED_DIR}/${app}"
    local app_yaml="${install_dir}/app.yaml"
    local display_name port

    display_name=$(yaml_get "$app_yaml" "display_name")
    port=$(yaml_get "$app_yaml" "port")

    # Get container status using tab delimiter to avoid colon issues
    local containers
    containers=$(compose_cmd "$install_dir" ps --format '{{.Name}}\t{{.Status}}' 2>/dev/null) || containers=""

    if [[ -z "$containers" ]]; then
      printf "  %-18s %-12s ${RED}%-30s${NC} %s\n" "$display_name" "$port" "stopped" "-"
      db_update_health "$app" "${app}" "stopped"
    else
      local first=true
      while IFS=$'\t' read -r cname cstatus; do
        [[ -z "$cname" ]] && continue

        # Color code status
        local color="${NC}"
        if [[ "$cstatus" == *"Up"* ]] || [[ "$cstatus" == *"running"* ]]; then
          color="${GREEN}"
          if [[ "$cstatus" == *"healthy"* ]]; then
            color="${GREEN}"
          elif [[ "$cstatus" == *"unhealthy"* ]]; then
            color="${RED}"
          fi
        elif [[ "$cstatus" == *"Exited"* ]] || [[ "$cstatus" == *"dead"* ]]; then
          color="${RED}"
        elif [[ "$cstatus" == *"Restarting"* ]]; then
          color="${YELLOW}"
        fi

        if $first; then
          printf "  %-18s %-12s ${color}%-30s${NC} %s\n" "$display_name" "$port" "$cstatus" "$cname"
          first=false
        else
          printf "  %-18s %-12s ${color}%-30s${NC} %s\n" "" "" "$cstatus" "$cname"
        fi

        # Cache health in DB
        db_update_health "$app" "$cname" "$cstatus"
      done <<< "$containers"
    fi
  done <<< "$apps"

  echo ""
}
