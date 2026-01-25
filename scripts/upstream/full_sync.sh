#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[FULL-SYNC]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

check_deps() {
  local deps=(bash)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Missing dependency: $cmd"
    fi
  done
  
  # Check if required scripts exist
  local scripts=("$SCRIPT_DIR/sync.sh" "$SCRIPT_DIR/../build/build.sh" "$SCRIPT_DIR/../publish/publish.sh" "$SCRIPT_DIR/../utils/validate.sh")
  for script in "${scripts[@]}"; do
    if [[ ! -f "$script" ]]; then
      err "Missing required script: $script"
    fi
  done
}

# --- Main ---

check_deps

log "Starting full sync and build pipeline..."
log ""

# Step 1: Sync upstream releases
log "Step 1/4: Syncing upstream releases..."
bash "$SCRIPT_DIR/sync.sh" || err "Upstream sync failed"
log ""

# Step 2: Build packages
log "Step 2/4: Building packages..."
bash "$SCRIPT_DIR/../build/build.sh" || err "Build failed"
log ""

# Step 3: Publish to repositories
log "Step 3/4: Publishing to repositories..."
bash "$SCRIPT_DIR/../publish/publish.sh" || err "Publishing failed"
log ""

# Step 4: Validate everything
log "Step 4/4: Validating repositories..."
bash "$SCRIPT_DIR/../utils/validate.sh" || err "Validation failed"
log ""

log "Full sync and build pipeline completed successfully!"
log ""
log "Summary:"
log "  ✓ Upstream releases synced"
log "  ✓ Packages built"
log "  ✓ Repositories updated"
log "  ✓ Validation passed"
log ""
log "Next steps:"
log "  1. Review changes: git status"
log "  2. Commit: git add . && git commit -m 'chore: sync upstream and update packages'"
log "  3. Push: git push origin main --tags"

