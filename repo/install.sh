#!/bin/bash
# Helium Browser One-Liner Installer for APT (Debian/Ubuntu)
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash

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
ARCH=$(dpkg --print-architecture)
print_status "Detected architecture: $ARCH"

# Add repository
print_status "Adding Helium Browser repository..."
echo "deb [arch=$ARCH] https://arvaidasre.github.io/helium-browser-deb/apt stable main" | sudo tee /etc/apt/sources.list.d/helium-browser.list

# Update package list
print_status "Updating package list..."
sudo apt-get update

# Install Helium Browser
print_status "Installing Helium Browser..."
sudo apt-get install -y helium-browser

print_status "Helium Browser has been successfully installed!"
print_status "Launch Helium Browser from your applications menu or run 'helium' in terminal."
