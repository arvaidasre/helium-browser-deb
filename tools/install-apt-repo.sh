#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://arvaidasre.github.io/helium-browser-deb/apt"
LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"
ARCH="amd64,arm64"
COMPONENT="main"

die() {
  echo "[helium] ERROR: $*" >&2
  exit 1
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
    echo "[helium] Unknown codename '$CODENAME' -> using 'stable'" >&2
    CODENAME="stable"
    ;;
esac

mkdir -p "$(dirname "$LIST_FILE")"
cat >"$LIST_FILE" <<EOF
deb [arch=$ARCH trusted=yes] $REPO_URL $CODENAME $COMPONENT
EOF

echo "[helium] Wrote: $LIST_FILE"
echo "[helium] Entry: deb [arch=$ARCH trusted=yes] $REPO_URL $CODENAME $COMPONENT"
