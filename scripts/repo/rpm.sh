#!/usr/bin/env bash
# ==============================================================================
# rpm.sh — Generate an RPM repository from packages in dist/
# ==============================================================================
# Usage: ./rpm.sh [REPO_DIR]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="RPM-REPO"

readonly REPO_DIR="${1:-site/public/rpm}"

# ── Dependencies ──────────────────────────────────────────────────────────────

if ! command -v createrepo_c >/dev/null 2>&1 && ! command -v createrepo >/dev/null 2>&1; then
  err "Missing: createrepo or createrepo_c (dnf install createrepo_c)"
fi

# ── Directory structure ───────────────────────────────────────────────────────

log "Generating RPM repository in $REPO_DIR..."

mkdir -p "$REPO_DIR/x86_64" "$REPO_DIR/aarch64"

# Copy .rpm files from dist/
[[ -d "dist" ]] || { warn "dist/ directory not found — repo will be empty."; }

for rpm_file in dist/*.rpm; do
  [[ -f "$rpm_file" ]] || continue
  if [[ "$rpm_file" == *x86_64* ]]; then
    log "Copying $(basename "$rpm_file") → x86_64"
    cp "$rpm_file" "$REPO_DIR/x86_64/"
  elif [[ "$rpm_file" == *aarch64* || "$rpm_file" == *arm64* ]]; then
    log "Copying $(basename "$rpm_file") → aarch64"
    cp "$rpm_file" "$REPO_DIR/aarch64/"
  else
    warn "Unknown arch for $(basename "$rpm_file"), defaulting to x86_64"
    cp "$rpm_file" "$REPO_DIR/x86_64/"
  fi
done

# ── Generate metadata ────────────────────────────────────────────────────────

cd "$REPO_DIR"

for arch in x86_64 aarch64; do
  if compgen -G "$arch/*.rpm" >/dev/null; then
    log "Generating metadata for $arch..."
    if command -v createrepo_c >/dev/null 2>&1; then
      createrepo_c --update "$arch" 2>/dev/null || createrepo_c "$arch"
    else
      createrepo --update "$arch" 2>/dev/null || createrepo "$arch"
    fi
  else
    err "No RPM packages for $arch in $REPO_DIR/$arch"
  fi
done

log "RPM repository generated: $REPO_DIR"
log "Config: baseurl=${HELIUM_REPO_URL}/rpm/\$basearch"
