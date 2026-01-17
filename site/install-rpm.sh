#!/bin/bash
# Helium Browser One-Liner Installer for DNF/YUM (Fedora/RHEL/CentOS)
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        REPO_ARCH="x86_64"
        ;;
    aarch64)
        REPO_ARCH="aarch64"
        ;;
    arm64)
        REPO_ARCH="aarch64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

print_status "Detected architecture: $REPO_ARCH"

# Add repository
print_status "Adding Helium Browser repository..."
sudo tee /etc/yum.repos.d/helium.repo > /dev/null << EOF
[helium]
name=Helium Browser Repository
baseurl=https://arvaidasre.github.io/helium-browser-deb/rpm/\$basearch
enabled=1
gpgcheck=0
metadata_expire=1h
EOF

# Install Helium Browser
if command -v dnf >/dev/null 2>&1; then
    print_status "Installing Helium Browser with DNF..."
    sudo dnf install -y helium-browser
elif command -v yum >/dev/null 2>&1; then
    print_status "Installing Helium Browser with YUM..."
    sudo yum install -y helium-browser
else
    print_error "Neither DNF nor YUM package manager found. Please install manually."
    exit 1
fi

print_status "Helium Browser has been successfully installed!"
print_status "Launch Helium Browser from your applications menu or run 'helium' in terminal."
