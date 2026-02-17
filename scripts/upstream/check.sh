#!/usr/bin/env bash
# ==============================================================================
# check.sh — Display information about the latest upstream release
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="CHECK"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps curl jq

# ── Fetch latest release ─────────────────────────────────────────────────────

log "Checking upstream: ${HELIUM_UPSTREAM_REPO}"

RESPONSE="$(github_api_get "https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/latest")"

TAG="$(jq -r '.tag_name // "null"' <<<"$RESPONSE")"
[[ "$TAG" == "null" ]] && err "Could not fetch latest release"

NAME="$(jq -r '.name // "null"' <<<"$RESPONSE")"
AUTHOR="$(jq -r '.author.login // "null"' <<<"$RESPONSE")"
CREATED="$(jq -r '.created_at // "null"' <<<"$RESPONSE")"
PUBLISHED="$(jq -r '.published_at // "null"' <<<"$RESPONSE")"
PRERELEASE="$(jq -r '.prerelease // false' <<<"$RESPONSE")"
DRAFT="$(jq -r '.draft // false' <<<"$RESPONSE")"
ASSET_COUNT="$(jq '.assets | length' <<<"$RESPONSE")"
BODY="$(jq -r '.body // ""' <<<"$RESPONSE")"

# ── Display ───────────────────────────────────────────────────────────────────

section "Latest Release"
log "Tag:         $TAG"
log "Name:        $NAME"
log "Author:      $AUTHOR"
log "Created:     $CREATED"
log "Published:   $PUBLISHED"
log "Pre-release: $PRERELEASE"
log "Draft:       $DRAFT"
log "Assets:      $ASSET_COUNT"

section "Release Notes (first 20 lines)"
echo "$BODY" | head -20 | sed 's/^/  /'
(( $(echo "$BODY" | wc -l) > 20 )) && log "  … (truncated)"

section "Assets"
jq -r '.assets[] | "  \(.name) (\(.size / 1048576 | round)MB)"' <<<"$RESPONSE" | head -10
(( ASSET_COUNT > 10 )) && log "  … and more"

section "Linux Tarballs"
jq -r '.assets[]
  | select(.name | test("linux"; "i"))
  | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
  | "  \(.name): \(.browser_download_url)"' <<<"$RESPONSE" | head -5

log ""
log "Release: ${HELIUM_UPSTREAM_URL}/releases/tag/$TAG"

