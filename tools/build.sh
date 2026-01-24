#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
UPSTREAM_REPO="imputnet/helium-linux"
OUTDIR="dist"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-common.sh"

# --- Main Logic ---

check_deps

mkdir -p "$OUTDIR"

# 1. Fetch Upstream Release Info
# If UPSTREAM_TAG is provided (from CI), use that specific release
# Otherwise, fetch the latest stable release
if [[ -n "${UPSTREAM_TAG:-}" ]]; then
  log "Using specified release tag: $UPSTREAM_TAG"
  API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${UPSTREAM_TAG}"
else
  log "Fetching latest stable release info from $UPSTREAM_REPO..."
  API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
fi
JSON="$(fetch_release_json "$API_URL")"

validate_release_json "$JSON"
TAG="$(jq -r '.tag_name' <<<"$JSON")"

VERSION="$(normalize_version "$TAG")"
log "Latest version: $VERSION (Tag: $TAG)"

# Check if this is a pre-release
PRERELEASE="$(jq -r '.prerelease // false' <<<"$JSON")"
if [[ "$PRERELEASE" == "true" || "$TAG" =~ (alpha|beta|rc|pre|preview) ]]; then
  IS_PRERELEASE="true"
  log "Detected pre-release: $TAG"
else
  IS_PRERELEASE="false"
fi

# 2. Check if we should skip (CI only, unless FORCE_BUILD is set)
SKIPPED="0"
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && "${FORCE_BUILD:-}" != "true" ]]; then
  log "Checking if release $TAG exists in $GITHUB_REPOSITORY..."
  HTTP_CODE="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}")"
  
  if [[ "$HTTP_CODE" == "200" ]]; then
    log "Release $TAG already exists. Skipping build."
    SKIPPED="1"
  fi

  # Check creation date of upstream release - don't build releases older than 2025-01-01
  UPSTREAM_CREATED_AT="$(jq -r '.created_at' <<<"$JSON")"
  log "Upstream release created at: $UPSTREAM_CREATED_AT"
  if [[ "$UPSTREAM_CREATED_AT" < "2025-01-01" ]]; then
    log "Upstream release is too old (pre-2025). Skipping."
    SKIPPED="1"
  fi
elif [[ "${FORCE_BUILD:-}" == "true" ]]; then
  log "FORCE_BUILD enabled - skipping existence check"
fi

# Save metadata for GitHub Actions
cat >"$OUTDIR/meta.env" <<EOF
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=${SKIPPED}
IS_PRERELEASE=${IS_PRERELEASE}
EOF

if [[ "$SKIPPED" == "1" ]]; then
  exit 0
fi

# 3. Get Assets URLs
set_arch_vars
log "Target Architecture: DEB=$DEB_ARCH, RPM=$RPM_ARCH (Pattern: $ASSET_PATTERN)"

TARBALL_URL="$(resolve_tarball_url "$JSON")"

if [[ -z "$TARBALL_URL" ]]; then
  err "Tarball asset not found for $TAG (arch pattern: $ASSET_PATTERN). Available assets:\n$(get_assets_summary "$JSON")"
fi

log "Tarball: $TARBALL_URL"

write_release_notes "$JSON" "$OUTDIR" "$TAG"

# 4. Prepare Build Environment
setup_workdir
build_offline_packages "$TARBALL_URL" "$OUTDIR"
