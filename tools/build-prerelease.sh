#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
UPSTREAM_REPO="imputnet/helium-linux"
OUTDIR="dist"
TARGET_TAG="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-common.sh"

# --- Main Logic ---

check_deps

mkdir -p "$OUTDIR"

# Use the provided tag
if [[ -z "$TARGET_TAG" ]]; then
  err "No target tag provided"
fi

TAG="$TARGET_TAG"
VERSION="$(normalize_version "$TAG")"
log "Building pre-release version: $VERSION (Tag: $TAG)"

# Save metadata for GitHub Actions
cat >"$OUTDIR/meta.env" <<EOF
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=0
IS_PRERELEASE=true
EOF

# 3. Get Assets URLs
set_arch_vars
log "Target Architecture: DEB=$DEB_ARCH, RPM=$RPM_ARCH (Pattern: $ASSET_PATTERN)"

# Get specific release info for the target tag
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG}"
JSON="$(fetch_release_json "$API_URL")"

validate_release_json "$JSON"

TARBALL_URL="$(resolve_tarball_url "$JSON")"

if [[ -z "$TARBALL_URL" ]]; then
  err "Tarball asset not found for $TAG (arch pattern: $ASSET_PATTERN). Available assets:\n$(get_assets_summary "$JSON")"
fi

log "Tarball: $TARBALL_URL"

write_release_notes "$JSON" "$OUTDIR" "$TAG"

# 4. Prepare Build Environment
setup_workdir
build_offline_packages "$TARBALL_URL" "$OUTDIR"
