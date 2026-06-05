#!/bin/bash

set -e

# =========================================================
# COLORS
# =========================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =========================================================
# ROOT CHECK
# =========================================================

if [ "$EUID" -ne 0 ]; then
    error "Run script as root"
    exit 1
fi

# =========================================================
# DETECT UBUNTU VERSION
# =========================================================

source /etc/os-release

UBUNTU_CODENAME="$VERSION_CODENAME"

info "Detected Ubuntu codename: $UBUNTU_CODENAME"

case "$UBUNTU_CODENAME" in
    jammy|noble|bookworm)
        success "Supported OS version"
        ;;
    *)
        error "Unsupported OS version: $UBUNTU_CODENAME"
        exit 1
        ;;
esac

# =========================================================
# INSTALL DEPENDENCIES
# =========================================================

info "Installing dependencies..."

apt update

apt install -y \
    wget \
    curl \
    gnupg2 \
    lsb-release \
    ca-certificates

success "Dependencies installed"

# =========================================================
# ADD OPENSIPS REPOSITORY
# =========================================================

REPO_FILE="/etc/apt/sources.list.d/opensips.list"
KEY_FILE="/usr/share/keyrings/opensips.gpg"

info "Adding OpenSIPS repository..."

if [ "$UBUNTU_CODENAME" = "bookworm" ]; then
    REPO_DIST="bookworm"
else
    REPO_DIST="$UBUNTU_CODENAME"
fi

echo "deb [signed-by=$KEY_FILE] https://apt.opensips.org $REPO_DIST 3.4-releases" > "$REPO_FILE"

success "Repository added"

# =========================================================
# IMPORT GPG KEY
# =========================================================

info "Importing GPG key..."

wget -qO- https://apt.opensips.org/opensips-org.gpg | \
gpg --dearmor -o "$KEY_FILE"

chmod 644 "$KEY_FILE"

success "GPG key imported"

# =========================================================
# UPDATE PACKAGE LIST
# =========================================================

info "Updating package list..."

apt update

success "Package list updated"

# =========================================================
# INSTALL OPENSIPS
# =========================================================

info "Installing OpenSIPS..."

DEBIAN_FRONTEND=noninteractive apt install -y opensips
apt install -y python3-pip pipx
pipx ensurepath
pipx install opensipscli
echo 'export PATH=$PATH:/usr/sbin' >> ~/.bashrc
source ~/.bashrc
success "OpenSIPS installed"

# =========================================================
# ENABLE SERVICE
# =========================================================

info "Enabling OpenSIPS service..."

systemctl enable opensips
systemctl restart opensips

success "Service enabled and started"

# =========================================================
# CONFIG VALIDATION
# =========================================================

info "Validating OpenSIPS config..."

if opensips -C; then
    success "OpenSIPS configuration is valid"
else
    error "OpenSIPS configuration validation failed"
    exit 1
fi

# =========================================================
# STATUS
# =========================================================

info "OpenSIPS service status:"

systemctl --no-pager status opensips

# =========================================================
# FINISH
# =========================================================

echo
success "OpenSIPS installation completed"
echo

echo -e "${GREEN}Useful commands:${NC}"
echo "----------------------------------------"
echo "systemctl status opensips"
echo "journalctl -u opensips -f"
echo "opensips -C"
echo "opensips -F"
echo "opensips-cli -x mi get_statistics all"
echo "----------------------------------------"