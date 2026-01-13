#!/bin/bash
# Helium Browser One-Liner Installer for APT (Debian/Ubuntu)
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Detect architecture
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
log "Detected architecture: $ARCH"

# Check if apt is available
if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get not found. This script is for Debian/Ubuntu systems only."
fi

# Repository URL
REPO_URL="https://arvaidasre.github.io/helium-browser-deb/apt"
LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"

# Check if already installed
if dpkg -l | grep -q "^ii.*helium-browser"; then
    CURRENT_VERSION=$(dpkg -l | grep helium-browser | awk '{print $3}')
    log "Helium Browser is already installed (version: $CURRENT_VERSION)"
    log "Updating to latest version..."
else
    log "Installing Helium Browser..."
fi

# Remove old repository entry if exists (for clean reinstall)
if [[ -f "$LIST_FILE" ]]; then
    log "Removing old repository configuration..."
    $SUDO rm -f "$LIST_FILE"
fi

# Add repository
log "Adding Helium Browser repository..."
echo "deb [arch=$ARCH trusted=yes] $REPO_URL stable main" | $SUDO tee "$LIST_FILE" > /dev/null

# Update package list
log "Updating package list..."
$SUDO apt-get update -qq

# Install Helium Browser
log "Installing helium-browser package..."
$SUDO apt-get install -y helium-browser

# Verify installation
if command -v helium >/dev/null 2>&1; then
    log "Helium Browser has been successfully installed!"
    echo ""
    echo -e "${BLUE}Launch Helium Browser:${NC}"
    echo "  - From applications menu, or"
    echo "  - Run 'helium' in terminal"
    echo ""
else
    warn "Installation completed but 'helium' command not found in PATH."
    warn "Try launching from /usr/bin/helium or restart your terminal."
fi
