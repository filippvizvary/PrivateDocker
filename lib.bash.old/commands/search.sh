#!/bin/bash
# homestack search [query]

cmd_run() {
  local query="${1:-}"
  local results

  if [[ -z "$query" ]]; then
    results=$(registry_list)
  else
    results=$(registry_search "$query")
  fi

  if [[ -z "$results" ]]; then
    echo "No apps found${query:+ matching '${query}'}."
    echo "  Try 'homestack catalog update' to refresh the catalog."
    exit 0
  fi

  echo -e "${BLUE}Available Apps${NC}"
  echo ""
  printf "  %-18s %-15s %-8s %s\n" "NAME" "CATEGORY" "PORT" "DESCRIPTION"
  printf "  %-18s %-15s %-8s %s\n" "----" "--------" "----" "-----------"

  while IFS='|' read -r name display description category port; do
    local installed_marker=""
    is_installed "$name" && installed_marker=" ✓"
    printf "  %-18s %-15s %-8s %s%s\n" "$name" "$category" "$port" "$description" "$installed_marker"
  done <<< "$results"

  echo ""
  echo "  Install with: homestack install <name>"
  echo "  ✓ = already installed"
  echo ""
}
