#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
WORKDIR="/work"
DIST_DIR="${DIST_DIR:-dist}"
ARCHES_DEFAULT=(amd64 arm64)

# --- Helper Functions ---
log() { echo -e "\033[1;34m[DOCKER-BUILD]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# --- Main ---

if [[ ! -d "$WORKDIR" ]]; then
  err "Workdir not found: $WORKDIR"
fi

cd "$WORKDIR"

arches=()
if [[ -n "${ARCHES:-}" ]]; then
  # shellcheck disable=SC2206
  arches=(${ARCHES})
else
  arches=("${ARCHES_DEFAULT[@]}")
fi

log "Building arches: ${arches[*]}"

for arch in "${arches[@]}"; do
  log "Building for $arch"
  ARCH_OVERRIDE="$arch" ./scripts/build.sh

  if [[ ! -d "$DIST_DIR" ]]; then
    err "Distribution directory not found: $DIST_DIR"
  fi

  mkdir -p "$DIST_DIR/$arch"
  mv "$DIST_DIR"/*.deb "$DIST_DIR/$arch/" 2>/dev/null || true
  mv "$DIST_DIR"/*.rpm "$DIST_DIR/$arch/" 2>/dev/null || true
  mv "$DIST_DIR"/SHA256SUMS "$DIST_DIR/$arch/" 2>/dev/null || true
  mv "$DIST_DIR"/meta.env "$DIST_DIR/$arch/" 2>/dev/null || true
  mv "$DIST_DIR"/release_title.txt "$DIST_DIR/$arch/" 2>/dev/null || true
  mv "$DIST_DIR"/release_notes.md "$DIST_DIR/$arch/" 2>/dev/null || true

  log "Artifacts moved to $DIST_DIR/$arch"
done

log "Docker build complete."
