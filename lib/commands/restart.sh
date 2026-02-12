#!/bin/bash
# homestack restart [app]

cmd_run() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    if ! is_installed "$target"; then
      error "'${target}' is not installed."
      exit 1
    fi
    local install_dir="${INSTALLED_DIR}/${target}"
    local display_name
    display_name=$(yaml_get "${install_dir}/app.yaml" "display_name")
    step "Restarting ${display_name}"
    compose_cmd "$install_dir" down 2>/dev/null || true
    compose_cmd "$install_dir" up -d
    success "${display_name} restarted"
  else
    # Stop all, then start all
    source "${HOMESTACK_DIR}/lib/commands/stop.sh"
    cmd_run
    # Redefine cmd_run for start
    source "${HOMESTACK_DIR}/lib/commands/start.sh"
    cmd_run
  fi
}
