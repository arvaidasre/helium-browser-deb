#!/usr/bin/env bash
# ==============================================================================
# install_apt.sh — Add the Helium APT source list (run as root)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="INSTALL"

readonly LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"
readonly ARCH="amd64,arm64"
readonly COMPONENT="main"

# ── Root check ───────────────────────────────────────────────────────────────

if [[ "${EUID:-$(id -u)}" != "0" ]]; then
  err "Run as root (e.g. sudo $0)."
fi

# ── Detect codename ─────────────────────────────────────────────────────────

detect_codename() {
  local codename=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi
  if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  echo "${codename:-stable}"
}

CODENAME="$(detect_codename)"

case "$CODENAME" in
  noble|jammy|focal|bookworm|bullseye|stable) ;;
  *)
    warn "Unknown codename '$CODENAME' — falling back to 'stable'"
    CODENAME="stable"
    ;;
esac

# ── Write source list ───────────────────────────────────────────────────────

mkdir -p "$(dirname "$LIST_FILE")"
echo "deb [arch=$ARCH trusted=yes] ${HELIUM_REPO_URL}/apt $CODENAME $COMPONENT" > "$LIST_FILE"

log "Wrote: $LIST_FILE"
log "Entry: deb [arch=$ARCH trusted=yes] ${HELIUM_REPO_URL}/apt $CODENAME $COMPONENT"
