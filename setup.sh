#!/bin/bash
# ============================================================
# HomeStack — Setup & Bootstrap Script
# Installs Docker (if needed) and sets up HomeStack CLI
# ============================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step()    { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}!${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; }

# --- Pre-flight ---
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (sudo ./setup.sh)"
  exit 1
fi

INSTALL_DIR="${HOMESTACK_DIR:-/homestack}"
REPO_URL="https://github.com/filippvizvary/homestack.git"
APPS_REPO_URL="https://github.com/filippvizvary/homestack-apps.git"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        HomeStack Setup Script        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. Check dependencies
# ============================================================
step "Checking dependencies..."

# Check for sqlite3
if command -v sqlite3 &>/dev/null; then
  success "sqlite3 is available"
else
  step "Installing sqlite3..."
  if command -v apt &>/dev/null; then
    apt update -qq && apt install -y -qq sqlite3
  elif command -v dnf &>/dev/null; then
    dnf install -y -q sqlite
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm sqlite
  else
    error "sqlite3 is required but could not be installed automatically."
    echo "  Install it manually and re-run setup."
    exit 1
  fi
  success "sqlite3 installed"
fi

# Check for git
if command -v git &>/dev/null; then
  success "git is available"
else
  error "git is required. Install it and re-run setup."
  exit 1
fi

# ============================================================
# 2. Install Docker (if not present)
# ============================================================
step "Checking Docker installation..."
if command -v docker &>/dev/null; then
  DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
  success "Docker ${DOCKER_VERSION} is already installed"
else
  step "Installing Docker via official script..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  success "Docker installed and started"
fi

# Verify docker compose plugin
if docker compose version &>/dev/null; then
  success "Docker Compose plugin available"
else
  error "Docker Compose plugin not found. Install it: https://docs.docker.com/compose/install/"
  exit 1
fi

# ============================================================
# 3. Clone or update HomeStack
# ============================================================
step "Setting up HomeStack in ${INSTALL_DIR}..."
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  warn "HomeStack already installed at ${INSTALL_DIR}"
  read -rp "Update to latest version? [Y/n]: " update_choice
  update_choice="${update_choice:-Y}"
  if [[ "$update_choice" =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR"
    git pull --rebase
    success "Updated to latest version"
  fi
elif [[ -d "$INSTALL_DIR" ]] && [[ ! -d "${INSTALL_DIR}/.git" ]]; then
  warn "${INSTALL_DIR} exists but is not a git repo."
  warn "If running from a local copy, we'll configure in place."
else
  git clone "$REPO_URL" "$INSTALL_DIR"
  success "Cloned HomeStack to ${INSTALL_DIR}"
fi

cd "$INSTALL_DIR"

# ============================================================
# 4. Create data directories
# ============================================================
step "Creating data directories..."
mkdir -p "${INSTALL_DIR}/AppData"
mkdir -p "${INSTALL_DIR}/Backups"
mkdir -p "${INSTALL_DIR}/Media"
mkdir -p "${INSTALL_DIR}/installed"
mkdir -p "${INSTALL_DIR}/.cache"
success "Data directories created"

# ============================================================
# 5. Configure homestack.env
# ============================================================
CONFIG_FILE="${INSTALL_DIR}/config/homestack.env"

if [[ -f "$CONFIG_FILE" ]]; then
  warn "Configuration already exists at ${CONFIG_FILE}"
  read -rp "Reconfigure? [y/N]: " reconfig
  reconfig="${reconfig:-N}"
  if [[ ! "$reconfig" =~ ^[Yy]$ ]]; then
    step "Keeping existing configuration"
  else
    configure=true
  fi
else
  configure=true
fi

if [[ "${configure:-false}" == "true" ]]; then
  step "Configuring HomeStack..."
  echo ""

  # Timezone
  current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  read -rp "  Timezone [${current_tz}]: " user_tz
  user_tz="${user_tz:-$current_tz}"

  # User IDs
  REAL_USER="${SUDO_USER:-$USER}"
  default_uid=$(id -u "$REAL_USER" 2>/dev/null || echo "1000")
  default_gid=$(id -g "$REAL_USER" 2>/dev/null || echo "1000")

  read -rp "  User ID (PUID) [${default_uid}]: " user_puid
  user_puid="${user_puid:-$default_uid}"

  read -rp "  Group ID (PGID) [${default_gid}]: " user_pgid
  user_pgid="${user_pgid:-$default_gid}"

  # Apps repo URL
  read -rp "  App catalog repo [${APPS_REPO_URL}]: " user_apps_repo
  user_apps_repo="${user_apps_repo:-$APPS_REPO_URL}"

  mkdir -p "${INSTALL_DIR}/config"

  cat > "$CONFIG_FILE" <<EOF
# ============================================================
# HomeStack Global Configuration
# Generated by setup.sh on $(date -Iseconds)
# ============================================================

# Installation directory
HOMESTACK_DIR=${INSTALL_DIR}

# Data directories
APPDATA=${INSTALL_DIR}/AppData
BACKUPS=${INSTALL_DIR}/Backups
MEDIA=${INSTALL_DIR}/Media

# Timezone
TZ=${user_tz}

# User/Group IDs
PUID=${user_puid}
PGID=${user_pgid}
DOCKER_USER=${user_puid}:${user_pgid}

# App catalog repository
HOMESTACK_APPS_REPO=${user_apps_repo}
EOF

  success "Configuration written to ${CONFIG_FILE}"
fi

# ============================================================
# 6. Initialize database
# ============================================================
step "Initializing database..."
export HOMESTACK_DIR="${INSTALL_DIR}"
source "${INSTALL_DIR}/lib/yaml.sh"
source "${INSTALL_DIR}/lib/core.sh"
source "${INSTALL_DIR}/lib/db.sh"
db_init
success "Database initialized at ${INSTALL_DIR}/homestack.db"

# ============================================================
# 7. Sync app catalog
# ============================================================
step "Syncing app catalog..."
source "${INSTALL_DIR}/lib/secrets.sh"
source "${INSTALL_DIR}/lib/registry.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  # Load HOMESTACK_APPS_REPO from config if set
  HOMESTACK_APPS_REPO=$(grep '^HOMESTACK_APPS_REPO=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || echo "")
  [[ -n "$HOMESTACK_APPS_REPO" ]] && APPS_REPO_URL="$HOMESTACK_APPS_REPO"
fi
registry_sync || warn "Could not sync catalog. Run 'homestack catalog update' later."

# ============================================================
# 8. Set file permissions
# ============================================================
step "Setting permissions..."
chmod +x "${INSTALL_DIR}/bin/homestack"
find "${INSTALL_DIR}/lib" -name "*.sh" -exec chmod +x {} \;
success "Permissions set"

# ============================================================
# 9. Create CLI symlink
# ============================================================
step "Installing homestack CLI..."
SYMLINK="/usr/local/bin/homestack"
if [[ -L "$SYMLINK" ]]; then
  rm "$SYMLINK"
fi
ln -s "${INSTALL_DIR}/bin/homestack" "$SYMLINK"
success "CLI available as 'homestack' (${SYMLINK})"

# ============================================================
# 10. Add current user to docker group (if not already)
# ============================================================
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" != "root" ]]; then
  if ! groups "$REAL_USER" | grep -q docker; then
    step "Adding ${REAL_USER} to docker group..."
    usermod -aG docker "$REAL_USER"
    warn "Log out and back in for docker group to take effect"
  else
    success "${REAL_USER} is already in docker group"
  fi
fi

# ============================================================
# Done!
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     HomeStack setup complete! 🏠     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "  Get started:"
echo "    homestack catalog update      — Refresh app catalog"
echo "    homestack search              — Browse available apps"
echo "    homestack install <app>       — Install an app"
echo "    homestack status              — Check running apps"
echo ""
echo "  Configuration: ${CONFIG_FILE}"
echo "  Database:      ${INSTALL_DIR}/homestack.db"
echo "  App data:      ${INSTALL_DIR}/AppData/"
echo "  Backups:       ${INSTALL_DIR}/Backups/"
echo "  Media:         ${INSTALL_DIR}/Media/"
echo ""
