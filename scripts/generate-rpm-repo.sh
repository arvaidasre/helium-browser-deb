#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO_NAME="helium-browser"
REPO_URL="https://arvaidasre.github.io"
REPO_DIR="${1:-repo/rpm}"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[RPM-REPO]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

check_deps() {
  if ! command -v createrepo >/dev/null 2>&1 && ! command -v createrepo_c >/dev/null 2>&1; then
    err "Missing dependency: createrepo or createrepo_c (install with: sudo dnf install createrepo_c or sudo yum install createrepo)"
  fi
}

# --- Main Logic ---

check_deps

log "Generating RPM repository in $REPO_DIR..."

# Create directory structure
mkdir -p "$REPO_DIR/x86_64"
mkdir -p "$REPO_DIR/aarch64"

# Copy .rpm files from dist/ to appropriate architecture directories
if [[ -d "dist" ]]; then
  for rpm in dist/*.rpm; do
    if [[ -f "$rpm" ]]; then
      # Detect architecture from filename
      if [[ "$rpm" == *"x86_64"* ]]; then
        log "Copying $(basename "$rpm") to x86_64..."
        cp "$rpm" "$REPO_DIR/x86_64/"
      elif [[ "$rpm" == *"aarch64"* ]] || [[ "$rpm" == *"arm64"* ]]; then
        log "Copying $(basename "$rpm") to aarch64..."
        cp "$rpm" "$REPO_DIR/aarch64/"
      else
        log "Warning: Could not determine architecture for $(basename "$rpm"), copying to x86_64"
        cp "$rpm" "$REPO_DIR/x86_64/"
      fi
    fi
  done
else
  log "Warning: dist/ directory not found. Repository will be empty."
fi

# Generate repository metadata
cd "$REPO_DIR"

# For x86_64
if [[ -n "$(ls -A x86_64/*.rpm 2>/dev/null)" ]]; then
  log "Generating repository metadata for x86_64..."
  if command -v createrepo_c >/dev/null 2>&1; then
    createrepo_c --update x86_64 || createrepo_c x86_64
  else
    createrepo --update x86_64 || createrepo x86_64
  fi
else
  log "No x86_64 packages found, skipping metadata generation"
fi

# For aarch64
if [[ -n "$(ls -A aarch64/*.rpm 2>/dev/null)" ]]; then
  log "Generating repository metadata for aarch64..."
  if command -v createrepo_c >/dev/null 2>&1; then
    createrepo_c --update aarch64 || createrepo_c aarch64
  else
    createrepo --update aarch64 || createrepo aarch64
  fi
else
  log "No aarch64 packages found, skipping metadata generation"
fi

log "RPM repository generated successfully!"
log "Repository location: $REPO_DIR"
log ""
log "To use this repository, create /etc/yum.repos.d/helium.repo:"
log "  [helium]"
log "  name=Helium Browser Repository"
log "  baseurl=$REPO_URL/rpm/\$basearch"
log "  enabled=1"
log "  gpgcheck=0"
