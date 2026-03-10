#!/bin/bash
# HomeStack Setup for Minimal Debian Installs
# This script handles minimal Debian environments that lack sudo, proper PATH, and basic utilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Use: su -c 'bash setup-minimal-debian.sh'"
fi

info "HomeStack Setup for Minimal Debian"
echo ""

# Step 1: Fix PATH for current session
info "Setting up PATH..."
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
success "PATH configured"

# Step 2: Update package lists
info "Updating package lists..."
apt-get update -qq || error "Failed to update package lists"
success "Package lists updated"

# Step 3: Install sudo
info "Installing sudo..."
if ! command -v sudo &> /dev/null; then
    apt-get install -y sudo || error "Failed to install sudo"
    success "sudo installed"
else
    success "sudo already installed"
fi

# Step 4: Install essential packages
info "Installing essential packages..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 || error "Failed to install essential packages"
success "Essential packages installed"

# Step 5: Create homestack user if it doesn't exist
HOMESTACK_USER="homestack"
if ! id "$HOMESTACK_USER" &> /dev/null; then
    info "Creating $HOMESTACK_USER user..."
    useradd -r -m -d /home/$HOMESTACK_USER -s /bin/bash $HOMESTACK_USER || error "Failed to create user"
    success "User $HOMESTACK_USER created"
else
    success "User $HOMESTACK_USER already exists"
fi

# Step 6: Add homestack user to sudo group
info "Adding $HOMESTACK_USER to sudo group..."
usermod -aG sudo $HOMESTACK_USER || error "Failed to add user to sudo group"
success "User added to sudo group"

# Step 7: Configure sudoers for homestack user (no password for docker commands)
info "Configuring sudo for $HOMESTACK_USER..."
cat > /etc/sudoers.d/homestack <<EOF
$HOMESTACK_USER ALL=(ALL) NOPASSWD: /usr/bin/docker
$HOMESTACK_USER ALL=(ALL) NOPASSWD: /usr/bin/docker-compose
$HOMESTACK_USER ALL=(ALL) NOPASSWD: /usr/local/bin/docker
$HOMESTACK_USER ALL=(ALL) NOPASSWD: /usr/local/bin/docker-compose
EOF
chmod 0440 /etc/sudoers.d/homestack
success "sudo configured for $HOMESTACK_USER"

# Step 8: Install Docker
info "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    
    # Install Docker
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error "Failed to install Docker"
    
    # Start Docker service
    systemctl start docker
    systemctl enable docker
    success "Docker installed and started"
else
    success "Docker already installed"
fi

# Step 9: Add homestack user to docker group
info "Adding $HOMESTACK_USER to docker group..."
usermod -aG docker $HOMESTACK_USER || error "Failed to add user to docker group"
success "User added to docker group"

# Step 10: Download/clone HomeStack
HOMESTACK_DIR="/homestack"
info "Setting up HomeStack in $HOMESTACK_DIR..."

if [ -d "$HOMESTACK_DIR" ]; then
    warn "Directory $HOMESTACK_DIR already exists"
    read -p "Remove and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOMESTACK_DIR"
    else
        error "Installation cancelled"
    fi
fi

git clone https://github.com/filippvizvary/homestack.git "$HOMESTACK_DIR" || error "Failed to clone HomeStack repository"
cd "$HOMESTACK_DIR"
success "HomeStack repository cloned"

# Step 11: Set ownership
info "Setting file ownership..."
chown -R $HOMESTACK_USER:$HOMESTACK_USER "$HOMESTACK_DIR"
success "File ownership set"

# Step 12: Run the main setup script as root
info "Running HomeStack setup..."
bash "$HOMESTACK_DIR/setup.sh" || error "HomeStack setup failed"

# Step 13: Create symlink in /usr/local/bin for global access
info "Creating global command symlink..."
ln -sf "$HOMESTACK_DIR/bin/homestack" /usr/local/bin/homestack
success "Global command created"

# Step 14: Fix PATH for all users (add to /etc/profile)
info "Configuring system-wide PATH..."
if ! grep -q "/usr/local/sbin" /etc/profile; then
    cat >> /etc/profile <<'EOF'

# HomeStack: Ensure standard paths are available
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
EOF
    success "System-wide PATH configured"
else
    success "System-wide PATH already configured"
fi

echo ""
success "═══════════════════════════════════════════════════════════"
success "HomeStack installation complete!"
success "═══════════════════════════════════════════════════════════"
echo ""
info "Next steps:"
echo "  1. Log out and log back in (or run: su - $HOMESTACK_USER)"
echo "  2. Run: homestack search"
echo "  3. Install an app: homestack install <app>"
echo ""
info "For other users to access the homestack command:"
echo "  Either use the full path: $HOMESTACK_DIR/bin/homestack"
echo "  Or add this to their .bashrc: export PATH=\"$HOMESTACK_DIR/bin:\$PATH\""
echo ""
