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

HOMESTACK_USER="homestack"
HOMESTACK_GROUP="homestack"
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
  step "Installing git..."
  if command -v apt &>/dev/null; then
    apt update -qq && apt install -y -qq git
  elif command -v dnf &>/dev/null; then
    dnf install -y -q git
  elif command -v yum &>/dev/null; then
    yum install -y -q git
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm git
  else
    error "git is required but could not be installed automatically."
    echo "  Install it manually and re-run setup."
    exit 1
  fi
  success "git installed"
fi

# Check for curl
if command -v curl &>/dev/null; then
  success "curl is available"
else
  step "Installing curl..."
  if command -v apt &>/dev/null; then
    apt update -qq && apt install -y -qq curl
  elif command -v dnf &>/dev/null; then
    dnf install -y -q curl
  elif command -v yum &>/dev/null; then
    yum install -y -q curl
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm curl
  else
    error "curl is required but could not be installed automatically."
    exit 1
  fi
  success "curl installed"
fi

# ============================================================
# 2. Install Docker & Compose (if not present)
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

# Install Docker Compose plugin if missing
step "Checking Docker Compose plugin..."
if docker compose version &>/dev/null; then
  COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || docker compose version | awk '{print $NF}')
  success "Docker Compose ${COMPOSE_VERSION} is available"
else
  step "Installing Docker Compose plugin..."
  if command -v apt &>/dev/null; then
    apt update -qq && apt install -y -qq docker-compose-plugin
  elif command -v dnf &>/dev/null; then
    dnf install -y -q docker-compose-plugin
  elif command -v yum &>/dev/null; then
    yum install -y -q docker-compose-plugin
  else
    error "Could not install Docker Compose plugin automatically."
    echo "  Install it manually: https://docs.docker.com/compose/install/"
    exit 1
  fi

  # Verify it installed correctly
  if docker compose version &>/dev/null; then
    success "Docker Compose plugin installed"
  else
    error "Docker Compose plugin installation failed."
    echo "  Install it manually: https://docs.docker.com/compose/install/"
    exit 1
  fi
fi

# ============================================================
# 3. Create homestack system user
# ============================================================
step "Setting up homestack system user..."

if id "$HOMESTACK_USER" &>/dev/null; then
  success "User '${HOMESTACK_USER}' already exists (UID=$(id -u "$HOMESTACK_USER"))"
else
  step "Creating system user '${HOMESTACK_USER}'..."
  useradd --system --create-home --home-dir "$INSTALL_DIR" \
    --shell /usr/sbin/nologin --comment "HomeStack service account" \
    "$HOMESTACK_USER"
  success "Created user '${HOMESTACK_USER}' (UID=$(id -u "$HOMESTACK_USER"))"
fi

# Ensure homestack group exists
if getent group "$HOMESTACK_GROUP" &>/dev/null; then
  success "Group '${HOMESTACK_GROUP}' already exists"
else
  groupadd --system "$HOMESTACK_GROUP"
  success "Created group '${HOMESTACK_GROUP}'"
fi

# Add homestack user to docker group so containers can be managed
if groups "$HOMESTACK_USER" | grep -q docker; then
  success "'${HOMESTACK_USER}' is already in docker group"
else
  usermod -aG docker "$HOMESTACK_USER"
  success "Added '${HOMESTACK_USER}' to docker group"
fi

# Add the calling user to homestack group so they can run the CLI
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" != "root" ]]; then
  if groups "$REAL_USER" | grep -q "$HOMESTACK_GROUP"; then
    success "'${REAL_USER}' is already in ${HOMESTACK_GROUP} group"
  else
    usermod -aG "$HOMESTACK_GROUP" "$REAL_USER"
    success "Added '${REAL_USER}' to ${HOMESTACK_GROUP} group"
    warn "Log out and back in for group membership to take effect"
  fi
fi

HOMESTACK_UID=$(id -u "$HOMESTACK_USER")
HOMESTACK_GID=$(id -g "$HOMESTACK_USER")

# ============================================================
# 4. Clone or update HomeStack
# ============================================================
step "Setting up HomeStack in ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
chown "${HOMESTACK_USER}:${HOMESTACK_GROUP}" "$INSTALL_DIR"
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
# 5. Create data directories
# ============================================================
step "Creating data directories..."
mkdir -p "${INSTALL_DIR}/AppData"
mkdir -p "${INSTALL_DIR}/Backups"
mkdir -p "${INSTALL_DIR}/Media"
mkdir -p "${INSTALL_DIR}/installed"
mkdir -p "${INSTALL_DIR}/.cache"
chown -R "${HOMESTACK_USER}:${HOMESTACK_GROUP}" "${INSTALL_DIR}/AppData" "${INSTALL_DIR}/Backups" "${INSTALL_DIR}/Media" "${INSTALL_DIR}/installed" "${INSTALL_DIR}/.cache"
chmod 2775 "${INSTALL_DIR}/AppData" "${INSTALL_DIR}/Backups" "${INSTALL_DIR}/Media" "${INSTALL_DIR}/installed"
success "Data directories created (owned by ${HOMESTACK_USER})"

# ============================================================
# 6. Configure homestack.env
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

  # User IDs (default to the homestack system user)
  read -rp "  User ID (PUID) [${HOMESTACK_UID}]: " user_puid
  user_puid="${user_puid:-$HOMESTACK_UID}"

  read -rp "  Group ID (PGID) [${HOMESTACK_GID}]: " user_pgid
  user_pgid="${user_pgid:-$HOMESTACK_GID}"

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
# 7. Initialize database
# ============================================================
step "Initializing database..."
export HOMESTACK_DIR="${INSTALL_DIR}"
source "${INSTALL_DIR}/lib/yaml.sh"
source "${INSTALL_DIR}/lib/core.sh"
source "${INSTALL_DIR}/lib/db.sh"
db_init
success "Database initialized at ${INSTALL_DIR}/homestack.db"

# ============================================================
# 8. Sync app catalog
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
# 9. Set file permissions & ownership
# ============================================================
step "Setting permissions and ownership..."
chmod +x "${INSTALL_DIR}/bin/homestack"
find "${INSTALL_DIR}/lib" -name "*.sh" -exec chmod +x {} \;

# Set ownership of the entire install directory
chown -R "${HOMESTACK_USER}:${HOMESTACK_GROUP}" "$INSTALL_DIR"

# Group-writable so members of homestack group can operate
chmod 2775 "$INSTALL_DIR"

# Protect secrets and database
find "${INSTALL_DIR}/installed" -name "secrets.env" -exec chmod 640 {} \; 2>/dev/null || true
[[ -f "${INSTALL_DIR}/homestack.db" ]] && chmod 660 "${INSTALL_DIR}/homestack.db"

success "Permissions set (owned by ${HOMESTACK_USER}:${HOMESTACK_GROUP})"

# ============================================================
# 10. Create CLI symlink
# ============================================================
step "Installing homestack CLI..."
SYMLINK="/usr/local/bin/homestack"
if [[ -L "$SYMLINK" ]]; then
  rm "$SYMLINK"
fi
ln -s "${INSTALL_DIR}/bin/homestack" "$SYMLINK"
success "CLI available as 'homestack' (${SYMLINK})"

# ============================================================
# Done!
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     HomeStack setup complete! 🏠     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "  System user:  ${HOMESTACK_USER} (UID=${HOMESTACK_UID}, GID=${HOMESTACK_GID})"
echo "  CLI user:     ${REAL_USER} (member of ${HOMESTACK_GROUP} group)"
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
