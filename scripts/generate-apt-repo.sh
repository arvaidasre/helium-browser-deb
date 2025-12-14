#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO_NAME="helium-browser"
REPO_URL="https://arvaidasre.github.io/helium-browser-deb"
REPO_DIR="${1:-repo/apt}"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[APT-REPO]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

check_deps() {
  local deps=(dpkg-scanpackages dpkg-scansources gzip)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Missing dependency: $cmd (install with: sudo apt-get install dpkg-dev)"
    fi
  done
}

# --- Main Logic ---

check_deps

log "Generating APT repository in $REPO_DIR..."

# Create directory structure
mkdir -p "$REPO_DIR/dists/stable/main/binary-amd64"
mkdir -p "$REPO_DIR/dists/stable/main/binary-arm64"
mkdir -p "$REPO_DIR/pool/main"

# Copy .deb files from dist/ to pool/main
if [[ -d "dist" ]]; then
  for deb in dist/*.deb; do
    if [[ -f "$deb" ]]; then
      log "Copying $(basename "$deb") to pool..."
      cp "$deb" "$REPO_DIR/pool/main/"
    fi
  done
else
  log "Warning: dist/ directory not found. Repository will be empty."
fi

# Generate Packages files
log "Generating Packages files..."
cd "$REPO_DIR"

# For amd64
if [[ -n "$(ls -A pool/main/*.deb 2>/dev/null)" ]]; then
  dpkg-scanpackages --arch amd64 pool/main > "dists/stable/main/binary-amd64/Packages" 2>/dev/null || touch "dists/stable/main/binary-amd64/Packages"
else
  touch "dists/stable/main/binary-amd64/Packages"
fi
gzip -k -f "dists/stable/main/binary-amd64/Packages" 2>/dev/null || true

# For arm64
if [[ -n "$(ls -A pool/main/*.deb 2>/dev/null)" ]]; then
  dpkg-scanpackages --arch arm64 pool/main > "dists/stable/main/binary-arm64/Packages" 2>/dev/null || touch "dists/stable/main/binary-arm64/Packages"
else
  touch "dists/stable/main/binary-arm64/Packages"
fi
gzip -k -f "dists/stable/main/binary-arm64/Packages" 2>/dev/null || true

# Generate Sources file (optional, but good practice)
if [[ -n "$(ls -A pool/main/*.deb 2>/dev/null)" ]]; then
  dpkg-scansources pool/main > "dists/stable/main/Sources" 2>/dev/null || touch "dists/stable/main/Sources"
else
  touch "dists/stable/main/Sources"
fi
gzip -k -f "dists/stable/main/Sources" 2>/dev/null || true

# Generate Release file
log "Generating Release file..."
cat > "dists/stable/Release" <<EOF
Origin: $REPO_NAME
Label: $REPO_NAME
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Helium Browser Repository
Date: $(date -u +"%a, %d %b %Y %H:%M:%S %Z")
EOF

# Add checksums (always add, even if files are empty)
# Use relative paths from Release file location
{
  echo "MD5Sum:"
  for f in dists/stable/main/binary-*/Packages* dists/stable/main/Sources*; do
    if [[ -f "$f" ]]; then
      SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
      HASH=$(md5sum "$f" | cut -d' ' -f1)
      REL_PATH="${f#dists/stable/}"
      printf " %s %8s %s\n" "$HASH" "$SIZE" "$REL_PATH"
    fi
  done
  echo "SHA256:"
  for f in dists/stable/main/binary-*/Packages* dists/stable/main/Sources*; do
    if [[ -f "$f" ]]; then
      SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
      HASH=$(sha256sum "$f" | cut -d' ' -f1)
      REL_PATH="${f#dists/stable/}"
      printf " %s %8s %s\n" "$HASH" "$SIZE" "$REL_PATH"
    fi
  done
} >> "dists/stable/Release"

log "APT repository generated successfully!"
log "Repository location: $REPO_DIR"
log ""
log "To use this repository, add to /etc/apt/sources.list.d/helium.list:"
log "  deb [arch=amd64,arm64] $REPO_URL/apt stable main"
