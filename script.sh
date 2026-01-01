#!/bin/bash
# --- Ensure root has access to admin commands permanently ---
if ! grep -q "/usr/sbin" /root/.bashrc; then
    echo 'export PATH="$PATH:/usr/sbin:/sbin"' >> /root/.bashrc
fi

# Apply PATH fix for this script execution
export PATH="$PATH:/usr/sbin:/sbin"


# --- Colors ---
BLUE="\e[94m\e[1m"   # Light blue + bold
NC="\e[0m"           # Reset color

step() {
    echo -e "${BLUE}[*] $1...${NC}"
}

success() {
    echo -e "${BLUE}[✓] $1${NC}"
}

# --- Ask for username ---
echo -e "${BLUE}Please specify user account to be used by Docker:${NC}"
read username

step "Updating system packages"
apt update && apt upgrade -y
success "System updated"

step "Installing required packages"
apt install -y ca-certificates curl zip unzip git
success "Base packages installed"

step "Creating keyring directory"
install -m 0755 -d /etc/apt/keyrings
success "Keyring directory ready"

step "Downloading Docker GPG key"
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
success "Docker GPG key installed"

step "Adding Docker repository"
tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
success "Docker repository added"

step "Updating package lists"
apt update
success "Package lists updated"

step "Installing Docker Engine and components"
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
success "Docker installed"

step "Starting Docker service"
systemctl start docker
success "Docker service started"

step "Creating docker group (if not exists)"
groupadd docker 2>/dev/null
success "Docker group ensured"

step "Adding user '$username' to docker group"
usermod -aG docker "$username"
success "User added to docker group"

step "Enabling Docker services"
systemctl enable docker.service
systemctl enable containerd.service
success "Docker services enabled"

step "Installing docker-compose plugin"
apt-get update
apt-get install -y docker-compose-plugin
success "docker-compose plugin installed"


step "Cloning PrivateDocker repository"
git clone https://github.com/filippvizvary/PrivateDocker /companyname/
success "Repository cloned"

step "Creating directories"
mkdir -p /companyname/AppData/
mkdir -p /companyname/Backup/
mkdir -p /companyname/Media/
success "Directories created"

# Find all .sh files and add execute permission
step "Setting execute permissions on .sh files"
find "/companyname" -type f -name "*.sh" -exec chmod +x {} \;
success "Execute permissions set"


chown -R $username:$username /companyname
echo -e "${BLUE}Setup completed successfully!${NC}"
