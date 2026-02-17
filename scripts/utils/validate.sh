#!/usr/bin/env bash
# ==============================================================================
# validate.sh — Validate APT + RPM repository structure
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="VALIDATE"

readonly APT_DIR="${1:-site/public/apt}"
readonly RPM_DIR="${2:-site/public/rpm}"
readonly SITE_DIR="${3:-site/public}"

# ── Local helpers ────────────────────────────────────────────────────────────

require_file() { [[ -f "$1" ]] || err "Missing file: $1"; }
require_dir()  { [[ -d "$1" ]] || err "Missing directory: $1"; }
require_grep() { grep -qE "$2" "$1" || err "Expected pattern '$2' in $1"; }

# ── Site root ────────────────────────────────────────────────────────────────

section "Site root files"
require_file "$SITE_DIR/index.html"
require_file "$SITE_DIR/install.sh"
require_file "$SITE_DIR/install-rpm.sh"

# ── APT repository ──────────────────────────────────────────────────────────

section "APT repository structure"
require_dir "$APT_DIR"
require_dir "$APT_DIR/dists/stable/main/binary-amd64"
require_dir "$APT_DIR/dists/stable/main/binary-arm64"
require_dir "$APT_DIR/pool/main"

require_file "$APT_DIR/dists/stable/Release"
require_grep "$APT_DIR/dists/stable/Release" '^Architectures: '
require_grep "$APT_DIR/dists/stable/Release" '^Components: '

for arch in amd64 arm64; do
  require_file "$APT_DIR/dists/stable/main/binary-$arch/Packages"
  require_file "$APT_DIR/dists/stable/main/binary-$arch/Packages.gz"
done

log "Checking APT distribution aliases..."
for dist in noble jammy focal bookworm bullseye; do
  require_file "$APT_DIR/dists/$dist/Release"
done

apt_pkg_count="$(find "$APT_DIR/pool/main" -maxdepth 1 -name '*.deb' | wc -l)"
log "APT packages in pool: $apt_pkg_count"
(( apt_pkg_count > 0 )) || err "No APT packages found."

# ── RPM repository ──────────────────────────────────────────────────────────

section "RPM repository structure"
require_dir "$RPM_DIR"
require_dir "$RPM_DIR/x86_64"
require_dir "$RPM_DIR/aarch64"

validate_rpm_metadata "$RPM_DIR/x86_64"
validate_rpm_metadata "$RPM_DIR/aarch64"

rpm_x86="$(find "$RPM_DIR/x86_64" -maxdepth 1 -name '*.rpm' | wc -l)"
rpm_arm="$(find "$RPM_DIR/aarch64" -maxdepth 1 -name '*.rpm' | wc -l)"
log "RPM packages x86_64: $rpm_x86"
log "RPM packages aarch64: $rpm_arm"
(( rpm_x86 > 0 )) || err "No RPM x86_64 packages found."
(( rpm_arm > 0 )) || err "No RPM aarch64 packages found."

# ── Manifest ─────────────────────────────────────────────────────────────────

section "Optional checks"
if [[ -f "$SITE_DIR/MANIFEST.txt" ]]; then
  log "[OK] Manifest: $SITE_DIR/MANIFEST.txt"
else
  warn "Manifest not found (optional)"
fi

section "Validation passed"
log "All repositories are properly configured."
