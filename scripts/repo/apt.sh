#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REPO_NAME="helium-browser"
REPO_URL="https://arvaidasre.github.io/helium-browser-deb"
REPO_DIR="${1:-site/public/apt}"

# Publish the same repo content under multiple APT distributions.
# This lets users use their system codename (e.g. noble, jammy) while keeping one pool.
# Override in CI via: APT_DISTS="stable noble jammy" ./tools/generate-apt-repo.sh
APT_DISTS_DEFAULT=(stable noble jammy focal bookworm bullseye)

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

APT_DISTS=()
if [[ -n "${APT_DISTS:-}" ]]; then
  # Split by whitespace
  # shellcheck disable=SC2206
  APT_DISTS=(${APT_DISTS})
else
  APT_DISTS=("${APT_DISTS_DEFAULT[@]}")
fi

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
  err "dist/ directory not found. Aborting to avoid empty repo."
fi

# Require packages for each arch
if ! ls -A "$REPO_DIR/pool/main"/*amd64*.deb >/dev/null 2>&1 && ! ls -A "$REPO_DIR/pool/main"/*x86_64*.deb >/dev/null 2>&1; then
  err "No amd64 .deb packages found in dist/."
fi

if ! ls -A "$REPO_DIR/pool/main"/*arm64*.deb >/dev/null 2>&1 && ! ls -A "$REPO_DIR/pool/main"/*aarch64*.deb >/dev/null 2>&1; then
  err "No arm64 .deb packages found in dist/."
fi

# Generate Packages files
log "Generating Packages files (with architecture filtering)..."
cd "$REPO_DIR"

# For amd64
if ! dpkg-scanpackages pool/main 2>&1 | awk -v RS='' -v ORS='\n\n' '/Architecture: (amd64|x86_64)/' > "dists/stable/main/binary-amd64/Packages"; then
  warn "dpkg-scanpackages failed for amd64"
fi
if [[ -s "dists/stable/main/binary-amd64/Packages" ]]; then
  if ! gzip -k -f "dists/stable/main/binary-amd64/Packages" 2>/dev/null; then
    err "Failed to gzip amd64 Packages"
  fi
else
  err "No amd64 packages found in pool/main"
fi

# For arm64
if ! dpkg-scanpackages pool/main 2>&1 | awk -v RS='' -v ORS='\n\n' '/Architecture: (arm64|aarch64)/' > "dists/stable/main/binary-arm64/Packages"; then
  warn "dpkg-scanpackages failed for arm64"
fi
if [[ -s "dists/stable/main/binary-arm64/Packages" ]]; then
  if ! gzip -k -f "dists/stable/main/binary-arm64/Packages" 2>/dev/null; then
    err "Failed to gzip arm64 Packages"
  fi
else
  err "No arm64 packages found in pool/main"
fi

# Generate Sources file (optional, but good practice) - don't fail if it doesn't work
if [[ -n "$(ls -A pool/main/*.deb 2>/dev/null)" ]]; then
  if dpkg-scansources pool/main > "dists/stable/main/Sources" 2>/dev/null; then
    gzip -k -f "dists/stable/main/Sources" 2>/dev/null || warn "Failed to gzip Sources"
  else
    warn "Failed to generate Sources file (this is optional)"
  fi
else
  warn "No .deb files found for Sources generation (this is optional)"
fi

# Generate Release file
log "Generating Release file..."
release_date=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S %Z")
cat > "dists/stable/Release" <<EOF
Origin: $REPO_NAME
Label: $REPO_NAME
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Helium Browser Repository
Date: $release_date
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

# Create per-codename distributions as copies of stable
log "Publishing distributions: ${APT_DISTS[*]}"
for dist in "${APT_DISTS[@]}"; do
  [[ "$dist" == "stable" ]] && continue

  rm -rf "dists/$dist"
  mkdir -p "dists/$dist"
  cp -a "dists/stable/"* "dists/$dist/"

  # Adjust metadata headers (checksums stay valid because files are identical)
  if [[ -f "dists/$dist/Release" ]]; then
    sed -i \
      -e "s/^Suite: .*/Suite: $dist/" \
      -e "s/^Codename: .*/Codename: $dist/" \
      "dists/$dist/Release"
  fi
done

log "APT repository generated successfully!"
log "Repository location: $REPO_DIR"
log ""
log "To use this repository, add to /etc/apt/sources.list.d/helium.list:"
log "  deb [arch=amd64,arm64] $REPO_URL/apt <codename|stable> main"
