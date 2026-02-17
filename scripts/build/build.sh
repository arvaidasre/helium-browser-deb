#!/usr/bin/env bash
# ==============================================================================
# build.sh — Fetch upstream release and build DEB + RPM packages
# ==============================================================================
set -euo pipefail

readonly OUTDIR="dist"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps curl jq fpm sha256sum

mkdir -p "$OUTDIR"

# ── 1. Fetch upstream release info ───────────────────────────────────────────

if [[ -n "${UPSTREAM_TAG:-}" ]]; then
  log "Using specified release tag: $UPSTREAM_TAG"
  API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/tags/${UPSTREAM_TAG}"
else
  log "Fetching latest stable release from ${HELIUM_UPSTREAM_REPO}..."
  API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/latest"
fi

JSON="$(github_api_get "$API_URL")"
validate_release_json "$JSON"

TAG="$(jq -r '.tag_name' <<<"$JSON")"
VERSION="$(normalize_version "$TAG")"
log "Version: $VERSION (tag: $TAG)"

# Detect pre-release
PRERELEASE="$(jq -r '.prerelease // false' <<<"$JSON")"
if [[ "$PRERELEASE" == "true" || "$TAG" =~ (alpha|beta|rc|pre|preview) ]]; then
  IS_PRERELEASE="true"
  log "Detected pre-release: $TAG"
else
  IS_PRERELEASE="false"
fi

# ── 2. Skip check (CI only, unless FORCE_BUILD is set) ───────────────────────

SKIPPED="0"
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && "${FORCE_BUILD:-}" != "true" ]]; then
  log "Checking if release $TAG already exists..."
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}")"

  if [[ "$HTTP_CODE" == "200" ]]; then
    log "Release $TAG already exists — skipping."
    SKIPPED="1"
  fi

  # Ignore releases created before 2025-01-01
  UPSTREAM_CREATED_AT="$(jq -r '.created_at' <<<"$JSON")"
  if [[ -n "$UPSTREAM_CREATED_AT" ]]; then
    CREATED_EPOCH="$(date -d "$UPSTREAM_CREATED_AT" +%s 2>/dev/null || echo 0)"
    MIN_EPOCH="$(date -d '2025-01-01' +%s 2>/dev/null || echo 0)"
    if (( CREATED_EPOCH < MIN_EPOCH )); then
      log "Upstream release too old ($UPSTREAM_CREATED_AT) — skipping."
      SKIPPED="1"
    fi
  fi
elif [[ "${FORCE_BUILD:-}" == "true" ]]; then
  log "FORCE_BUILD enabled — skipping existence check."
fi

# Save metadata for GitHub Actions
cat >"$OUTDIR/meta.env" <<META
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=${SKIPPED}
IS_PRERELEASE=${IS_PRERELEASE}
META

if [[ "$SKIPPED" == "1" ]]; then
  exit 0
fi

# ── 3. Resolve asset URL ─────────────────────────────────────────────────────

set_arch_vars
log "Architecture: DEB=$DEB_ARCH  RPM=$RPM_ARCH  (pattern: $ASSET_PATTERN)"

TARBALL_URL="$(resolve_tarball_url "$JSON")"
if [[ -z "$TARBALL_URL" ]]; then
  err "Tarball not found for $TAG (pattern: $ASSET_PATTERN).\\nAssets: $(get_assets_summary "$JSON")"
fi
log "Tarball: $TARBALL_URL"

write_release_notes "$JSON" "$OUTDIR" "$TAG"

# ── 4. Build packages ────────────────────────────────────────────────────────

setup_workdir
build_offline_packages "$TARBALL_URL" "$OUTDIR"
