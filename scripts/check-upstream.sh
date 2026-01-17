#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
UPSTREAM_REPO="imputnet/helium-linux"
GITHUB_API="https://api.github.com/repos/$UPSTREAM_REPO"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[CHECK]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# --- Main ---

log "Checking upstream repository: $UPSTREAM_REPO"
log ""

# Fetch latest release
log "Fetching latest release..."
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  RESPONSE=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$GITHUB_API/releases/latest")
else
  RESPONSE=$(curl -fsSL "$GITHUB_API/releases/latest")
fi

# Parse response
TAG=$(echo "$RESPONSE" | jq -r '.tag_name // "null"')
NAME=$(echo "$RESPONSE" | jq -r '.name // "null"')
AUTHOR=$(echo "$RESPONSE" | jq -r '.author.login // "null"')
CREATED=$(echo "$RESPONSE" | jq -r '.created_at // "null"')
PUBLISHED=$(echo "$RESPONSE" | jq -r '.published_at // "null"')
PRERELEASE=$(echo "$RESPONSE" | jq -r '.prerelease // false')
DRAFT=$(echo "$RESPONSE" | jq -r '.draft // false')
ASSET_COUNT=$(echo "$RESPONSE" | jq '.assets | length')
BODY=$(echo "$RESPONSE" | jq -r '.body // ""')

if [[ "$TAG" == "null" ]]; then
  err "Could not fetch latest release"
fi

log "Latest Release Information:"
log "  Tag: $TAG"
log "  Name: $NAME"
log "  Author: $AUTHOR"
log "  Created: $CREATED"
log "  Published: $PUBLISHED"
log "  Pre-release: $PRERELEASE"
log "  Draft: $DRAFT"
log "  Assets: $ASSET_COUNT"

log ""
log "Release Notes:"
echo "$BODY" | head -20 | sed 's/^/  /'
if [[ $(echo "$BODY" | wc -l) -gt 20 ]]; then
  log "  ... (truncated)"
fi

log ""
log "Assets:"
echo "$RESPONSE" | jq -r '.assets[] | "  \(.name) (\(.size | . / 1024 / 1024 | round)MB)"' | head -10

if [[ $(echo "$RESPONSE" | jq '.assets | length') -gt 10 ]]; then
  log "  ... and more"
fi

log ""
log "Download URLs:"
echo "$RESPONSE" | jq -r '.assets[] | select(.name | test("linux"; "i")) | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i")) | "  \(.name): \(.browser_download_url)"' | head -5

log ""
log "Repository URL: https://github.com/$UPSTREAM_REPO"
log "Release URL: https://github.com/$UPSTREAM_REPO/releases/tag/$TAG"

