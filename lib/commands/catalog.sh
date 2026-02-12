#!/bin/bash
# homestack catalog [update|list]

cmd_run() {
  local action="${1:-update}"

  case "$action" in
    update|sync)
      registry_sync
      ;;
    list)
      catalog_list
      ;;
    *)
      error "Unknown catalog action: ${action}"
      echo "Usage: homestack catalog [update|list]"
      exit 1
      ;;
  esac
}

catalog_list() {
  registry_ensure || exit 1

  echo -e "${BLUE}App Catalog${NC}"
  echo ""
  printf "  %-18s %-15s %-8s %s\n" "NAME" "CATEGORY" "PORT" "DESCRIPTION"
  printf "  %-18s %-15s %-8s %s\n" "----" "--------" "----" "-----------"

  for dir in "${APPS_DIR}"/*/; do
    [[ -f "${dir}app.yaml" ]] || continue
    local name display description category port
    name=$(yaml_get "${dir}app.yaml" "name")
    display=$(yaml_get "${dir}app.yaml" "display_name")
    description=$(yaml_get "${dir}app.yaml" "description")
    category=$(yaml_get "${dir}app.yaml" "category")
    port=$(yaml_get "${dir}app.yaml" "port")
    local installed_marker=""
    is_installed "$name" && installed_marker=" ${GREEN}✓${NC}"
    echo -e "  ${CYAN}${name}${NC}$(printf '%*s' $((18 - ${#name})) '') ${category}$(printf '%*s' $((15 - ${#category})) '') ${port}$(printf '%*s' $((8 - ${#port})) '') ${description}${installed_marker}"
  done

  echo ""
  echo "  Install with: homestack install <name>"
  echo -e "  ${GREEN}✓${NC} = already installed"
  echo ""
}
