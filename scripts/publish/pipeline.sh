#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[BUILD-PUBLISH]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# --- Main ---

log "Starting build and publish pipeline..."

# Step 1: Build packages
log "Step 1/3: Building packages..."
if [[ -f "$PROJECT_ROOT/scripts/build/build.sh" ]]; then
  bash "$PROJECT_ROOT/scripts/build/build.sh" || err "Build failed"
else
  err "build.sh not found"
fi

# Step 2: Validate build output
log "Step 2/3: Validating build output..."
if [[ ! -d "$PROJECT_ROOT/dist" ]] || [[ -z "$(ls -A "$PROJECT_ROOT/dist"/*.{deb,rpm} 2>/dev/null || true)" ]]; then
  err "No packages found in dist/ directory"
fi

# Step 3: Publish to repositories
log "Step 3/3: Publishing to repositories..."
bash "$SCRIPT_DIR/publish.sh" || err "Publishing failed"

log "Build and publish pipeline completed successfully!"
log ""
log "Summary:"
log "  - Packages built in: $PROJECT_ROOT/dist"
log "  - Repositories updated in: $PROJECT_ROOT/site/public"
log "  - Manifest generated: $PROJECT_ROOT/site/public/MANIFEST.txt"

