#!/usr/bin/env bash
# ==============================================================================
# checksum-verify.sh — Verify upstream tarball checksums
# ==============================================================================
# Usage: ./scripts/utils/checksum-verify.sh <tarball_path> <checksum_url>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="CHECKSUM"

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  
  if [[ "$actual" == "$expected" ]]; then
    log "✓ SHA256 checksum verified"
    return 0
  else
    err "SHA256 mismatch!\nExpected: $expected\nActual:   $actual"
  fi
}

verify_from_github_release() {
  local tarball_url="$1"
  local tarball_file="$2"
  local release_json="$3"
  
  log "Checking for SHA256 checksums in release assets..."
  
  # Try to find SHA256SUMS or similar file
  local checksum_url
  checksum_url=$(jq -r '.assets[]? | select(.name | test("sha256|checksum"; "i")) | .browser_download_url' <<<"$release_json" | head -1)
  
  if [[ -n "$checksum_url" && "$checksum_url" != "null" ]]; then
    log "Found checksum file: $checksum_url"
    local checksum_content
    checksum_content=$(curl -fsSL "$checksum_url")
    
    local filename
    filename=$(basename "$tarball_url")
    
    local expected_checksum
    expected_checksum=$(grep "$filename" <<<"$checksum_content" | awk '{print $1}' | head -1)
    
    if [[ -n "$expected_checksum" ]]; then
      verify_sha256 "$tarball_file" "$expected_checksum"
      return 0
    fi
  fi
  
  # Try to get checksum from release body
  local body_checksum
  body_checksum=$(jq -r '.body' <<<"$release_json" | \
    grep -oP '[a-f0-9]{64}' | head -1)
  
  if [[ -n "$body_checksum" ]]; then
    log "Found checksum in release notes"
    verify_sha256 "$tarball_file" "$body_checksum"
    return 0
  fi
  
  warn "No checksum found in release assets or notes"
  return 1
}

# Main
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <tarball_file> <checksum_source>"
  exit 1
fi

TARBALL_FILE="$1"
CHECKSUM_SOURCE="$2"

if [[ ! -f "$TARBALL_FILE" ]]; then
  err "Tarball not found: $TARBALL_FILE"
fi

if [[ "$CHECKSUM_SOURCE" =~ ^https?:// ]]; then
  # It's a URL to checksums file
  log "Downloading checksums from: $CHECKSUM_SOURCE"
  EXPECTED=$(curl -fsSL "$CHECKSUM_SOURCE" | grep "$(basename "$TARBALL_FILE")" | awk '{print $1}')
  verify_sha256 "$TARBALL_FILE" "$EXPECTED"
elif [[ -f "$CHECKSUM_SOURCE" ]]; then
  # It's a local JSON file (GitHub release)
  verify_from_github_release "" "$TARBALL_FILE" "$(cat "$CHECKSUM_SOURCE")"
elif [[ ${#CHECKSUM_SOURCE} -eq 64 ]]; then
  # It's a direct SHA256 hash
  verify_sha256 "$TARBALL_FILE" "$CHECKSUM_SOURCE"
else
  err "Unknown checksum source format: $CHECKSUM_SOURCE"
fi
