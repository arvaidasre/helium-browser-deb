#!/usr/bin/env bash
set -euo pipefail

APT_DIR="${1:-site/public/apt}"
RPM_DIR="${2:-site/public/rpm}"
SITE_DIR="${3:-site/public}"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[VALIDATE]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

require_file() {
  local f="$1"
  [[ -f "$f" ]] || err "Missing file: $f"
}

require_dir() {
  local d="$1"
  [[ -d "$d" ]] || err "Missing directory: $d"
}

require_grep() {
  local f="$1"
  local pat="$2"
  grep -qE "$pat" "$f" || err "Expected pattern '$pat' in $f"
}

check_file_integrity() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    return 1
  fi
  
  local size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
  if [[ "$size" -eq 0 ]]; then
    warn "Empty file: $f"
    return 1
  fi
  return 0
}

# --- Main ---

log "Validating repositories..."
log "APT repository: $APT_DIR"
log "RPM repository: $RPM_DIR"
log "Site root: $SITE_DIR"

# Check site root files
log ""
log "Checking site root files..."
require_file "$SITE_DIR/index.html"
require_file "$SITE_DIR/install.sh"
require_file "$SITE_DIR/install-rpm.sh"

# Check APT repository
log ""
log "Checking APT repository structure..."
require_dir "$APT_DIR"
require_dir "$APT_DIR/dists/stable/main/binary-amd64"
require_dir "$APT_DIR/dists/stable/main/binary-arm64"
require_dir "$APT_DIR/pool/main"

require_file "$APT_DIR/dists/stable/Release"
require_grep "$APT_DIR/dists/stable/Release" '^Architectures: '
require_grep "$APT_DIR/dists/stable/Release" '^Components: '

require_file "$APT_DIR/dists/stable/main/binary-amd64/Packages"
require_file "$APT_DIR/dists/stable/main/binary-amd64/Packages.gz"
require_file "$APT_DIR/dists/stable/main/binary-arm64/Packages"
require_file "$APT_DIR/dists/stable/main/binary-arm64/Packages.gz"

log "Checking APT distribution aliases..."
for dist in noble jammy focal bookworm bullseye; do
  require_file "$APT_DIR/dists/$dist/Release"
done

# Count packages
apt_pkg_count=$(ls -1 "$APT_DIR/pool/main"/*.deb 2>/dev/null | wc -l || echo "0")
log "APT packages in pool: $apt_pkg_count"
[[ "$apt_pkg_count" -gt 0 ]] || err "No APT packages found."

# Check RPM repository
log ""
log "Checking RPM repository structure..."
require_dir "$RPM_DIR"
require_dir "$RPM_DIR/x86_64"
require_dir "$RPM_DIR/aarch64"

require_file "$RPM_DIR/x86_64/repodata/repomd.xml"
require_file "$RPM_DIR/aarch64/repodata/repomd.xml"
require_grep "$RPM_DIR/x86_64/repodata/repomd.xml" '<repomd'
require_grep "$RPM_DIR/aarch64/repodata/repomd.xml" '<repomd'

# Count packages
rpm_x86_count=$(ls -1 "$RPM_DIR/x86_64"/*.rpm 2>/dev/null | wc -l || echo "0")
rpm_arm_count=$(ls -1 "$RPM_DIR/aarch64"/*.rpm 2>/dev/null | wc -l || echo "0")
log "RPM packages x86_64: $rpm_x86_count"
log "RPM packages aarch64: $rpm_arm_count"
[[ "$rpm_x86_count" -gt 0 ]] || err "No RPM x86_64 packages found."
[[ "$rpm_arm_count" -gt 0 ]] || err "No RPM aarch64 packages found."

# Check manifest
log ""
if [[ -f "$SITE_DIR/MANIFEST.txt" ]]; then
  log "Manifest file found: $SITE_DIR/MANIFEST.txt"
else
  warn "Manifest file not found (optional)"
fi

log ""
log "Validation completed successfully!"
log "All repositories are properly configured and ready for use."
