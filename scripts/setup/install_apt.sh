#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://arvaidasre.github.io/helium-browser-deb/apt"
LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"
ARCH="amd64,arm64"
COMPONENT="main"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[INSTALL]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

die() {
  err "$*"
}

need_root() {
  if [[ "${EUID:-$(id -u)}" != "0" ]]; then
    die "Run as root (e.g. sudo $0)."
  fi
}

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

  if [[ -z "$codename" ]]; then
    codename="stable"
  fi

  echo "$codename"
}

need_root

CODENAME="$(detect_codename)"

# If we haven't published a matching dists/<codename>, fall back to stable.
case "$CODENAME" in
  noble|jammy|focal|bookworm|bullseye|stable) ;;  # known/published
  *)
    warn "Unknown codename '$CODENAME' -> using 'stable'"
    CODENAME="stable"
    ;;
esac

mkdir -p "$(dirname "$LIST_FILE")"
cat >"$LIST_FILE" <<EOF
deb [arch=$ARCH trusted=yes] $REPO_URL $CODENAME $COMPONENT
EOF

log "Wrote: $LIST_FILE"
log "Entry: deb [arch=$ARCH trusted=yes] $REPO_URL $CODENAME $COMPONENT"
