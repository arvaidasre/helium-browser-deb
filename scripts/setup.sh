#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[SETUP]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# --- Main ---

log "Setting up Helium Browser packaging repository..."
log ""

# Check OS
if [[ ! -f /etc/os-release ]]; then
  err "This script requires a Linux system"
fi

source /etc/os-release

log "Detected OS: $PRETTY_NAME"
log ""

# Install dependencies based on OS
if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
  log "Installing Debian/Ubuntu dependencies..."
  sudo apt-get update
  sudo apt-get install -y \
    curl \
    jq \
    git \
    dpkg-dev \
    ruby-dev \
    build-essential \
    createrepo-c
  
  # Install FPM
  if ! command -v fpm >/dev/null 2>&1; then
    log "Installing FPM..."
    sudo gem install fpm
  fi
  
elif [[ "$ID" == "fedora" || "$ID" == "rhel" || "$ID" == "centos" ]]; then
  log "Installing Fedora/RHEL/CentOS dependencies..."
  sudo dnf install -y \
    curl \
    jq \
    git \
    rpm-build \
    ruby-devel \
    gcc \
    make \
    createrepo_c
  
  # Install FPM
  if ! command -v fpm >/dev/null 2>&1; then
    log "Installing FPM..."
    sudo gem install fpm
  fi
  
else
  warn "Unsupported OS: $ID"
  warn "Please install the following manually:"
  warn "  - curl, jq, git"
  warn "  - dpkg-dev (Debian/Ubuntu) or rpm-build (Fedora/RHEL)"
  warn "  - createrepo_c"
  warn "  - fpm (gem install fpm)"
fi

log ""
log "Creating necessary directories..."
mkdir -p "$PROJECT_ROOT/dist"
mkdir -p "$PROJECT_ROOT/repo/apt/pool/main"
mkdir -p "$PROJECT_ROOT/repo/rpm/x86_64"
mkdir -p "$PROJECT_ROOT/repo/rpm/aarch64"
mkdir -p "$PROJECT_ROOT/releases"
mkdir -p "$PROJECT_ROOT/.backups"

log ""
log "Making scripts executable..."
chmod +x "$SCRIPT_DIR"/*.sh

log ""
log "Setup completed successfully!"
log ""
log "Next steps:"
log "  1. Review RELEASE_PROCESS.md for detailed documentation"
log "  2. Run: bash scripts/full-sync-and-build.sh"
log "  3. Or run individual steps:"
log "     - bash scripts/sync-upstream.sh"
log "     - bash scripts/build.sh"
log "     - bash scripts/publish-release.sh"
log ""
log "For more information, see:"
log "  - RELEASE_PROCESS.md - Complete release process documentation"
log "  - README.md - Installation and usage instructions"

