#!/usr/bin/env bash
# ==============================================================================
# prerelease.sh — Build packages for a specific (pre-)release tag
# ==============================================================================
# Usage: ./prerelease.sh <TAG>
# ==============================================================================
set -euo pipefail

readonly OUTDIR="dist"
readonly TARGET_TAG="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps curl jq fpm sha256sum

mkdir -p "$OUTDIR"

[[ -z "$TARGET_TAG" ]] && err "Usage: $0 <TAG>"

TAG="$TARGET_TAG"
VERSION="$(normalize_version "$TAG")"
log "Building pre-release: $VERSION (tag: $TAG)"

# Save metadata
cat >"$OUTDIR/meta.env" <<META
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=0
IS_PRERELEASE=true
META

# ── Resolve assets ────────────────────────────────────────────────────────────

set_arch_vars
log "Architecture: DEB=$DEB_ARCH  RPM=$RPM_ARCH  (pattern: $ASSET_PATTERN)"

API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/tags/${TAG}"
JSON="$(github_api_get "$API_URL")"
validate_release_json "$JSON"

TARBALL_URL="$(resolve_tarball_url "$JSON")"
if [[ -z "$TARBALL_URL" ]]; then
  err "Tarball not found for $TAG (pattern: $ASSET_PATTERN).\\nAssets: $(get_assets_summary "$JSON")"
fi
log "Tarball: $TARBALL_URL"

write_release_notes "$JSON" "$OUTDIR" "$TAG"

# ── Build ─────────────────────────────────────────────────────────────────────

setup_workdir
build_offline_packages "$TARBALL_URL" "$OUTDIR"
