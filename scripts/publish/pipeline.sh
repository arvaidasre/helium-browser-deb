#!/usr/bin/env bash
# ==============================================================================
# pipeline.sh — End-to-end: build → validate → publish
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="PIPELINE"

# ── Step 1: Build ─────────────────────────────────────────────────────────────

log "Step 1/3 — Building packages..."
bash "$HELIUM_PROJECT_ROOT/scripts/build/build.sh" || err "Build failed"

# ── Step 2: Validate ──────────────────────────────────────────────────────────

log "Step 2/3 — Validating build output..."
shopt -s nullglob
pkgs=("$HELIUM_PROJECT_ROOT"/dist/*.deb "$HELIUM_PROJECT_ROOT"/dist/*.rpm)
shopt -u nullglob

if (( ${#pkgs[@]} == 0 )); then
  err "No packages found in dist/"
fi

# ── Step 3: Publish ───────────────────────────────────────────────────────────

log "Step 3/3 — Publishing..."
bash "$SCRIPT_DIR/publish.sh" || err "Publishing failed"

log "Pipeline completed successfully."
log "  Packages: $HELIUM_PROJECT_ROOT/dist"
log "  Repos:    $HELIUM_PROJECT_ROOT/site/public"

