#!/usr/bin/env bash
# ==============================================================================
# full_sync.sh — End-to-end: sync → build → publish → validate
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="FULL-SYNC"

# ── Validate prerequisites ───────────────────────────────────────────────────

readonly -a REQUIRED_SCRIPTS=(
  "$SCRIPT_DIR/sync.sh"
  "$SCRIPT_DIR/../build/build.sh"
  "$SCRIPT_DIR/../publish/publish.sh"
  "$SCRIPT_DIR/../utils/validate.sh"
)

for s in "${REQUIRED_SCRIPTS[@]}"; do
  [[ -f "$s" ]] || err "Missing required script: $s"
done

# ── Pipeline ─────────────────────────────────────────────────────────────────

readonly -a STEPS=(
  "sync.sh|Syncing upstream releases"
  "../build/build.sh|Building packages"
  "../publish/publish.sh|Publishing to repositories"
  "../utils/validate.sh|Validating repositories"
)

log "Starting full sync pipeline..."

step=0
total=${#STEPS[@]}

for entry in "${STEPS[@]}"; do
  (( step++ ))
  script="${entry%%|*}"
  label="${entry#*|}"
  section "Step $step/$total: $label"
  bash "$SCRIPT_DIR/$script" || err "$label failed"
done

section "Pipeline complete"
log "[OK] Upstream releases synced"
log "[OK] Packages built"
log "[OK] Repositories updated"
log "[OK] Validation passed"

