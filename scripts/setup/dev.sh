#!/usr/bin/env bash
# ==============================================================================
# dev.sh — Bootstrap a development environment for this repository
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="SETUP"

# ── OS detection ─────────────────────────────────────────────────────────────

[[ -f /etc/os-release ]] || err "This script requires a Linux system"

# shellcheck disable=SC1091
source /etc/os-release
log "Detected OS: $PRETTY_NAME"

# ── Install dependencies ────────────────────────────────────────────────────

section "Installing dependencies"

if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
  sudo apt-get update
  sudo apt-get install -y \
    curl jq git dpkg-dev ruby-dev build-essential createrepo-c
  command -v fpm >/dev/null 2>&1 || { log "Installing FPM..."; sudo gem install fpm; }

elif [[ "$ID" == "fedora" || "$ID" == "rhel" || "$ID" == "centos" ]]; then
  sudo dnf install -y \
    curl jq git rpm-build ruby-devel gcc make createrepo_c
  command -v fpm >/dev/null 2>&1 || { log "Installing FPM..."; sudo gem install fpm; }

else
  warn "Unsupported OS: $ID"
  warn "Install manually: curl, jq, git, dpkg-dev|rpm-build, createrepo_c, fpm"
fi

# ── Project directories ─────────────────────────────────────────────────────

section "Creating directories"

mkdir -p \
  "$HELIUM_PROJECT_ROOT/dist" \
  "$HELIUM_PROJECT_ROOT/site/public/apt/pool/main" \
  "$HELIUM_PROJECT_ROOT/site/public/rpm/x86_64" \
  "$HELIUM_PROJECT_ROOT/site/public/rpm/aarch64" \
  "$HELIUM_PROJECT_ROOT/releases" \
  "$HELIUM_PROJECT_ROOT/.backups"

# ── Permissions ──────────────────────────────────────────────────────────────

section "Making scripts executable"
find "$HELIUM_PROJECT_ROOT/scripts" -name '*.sh' -exec chmod +x {} +

section "Setup complete"
log "Next steps:"
log "  1. bash scripts/upstream/full_sync.sh   — full pipeline"
log "  2. bash scripts/build/build.sh          — build only"
log "  3. bash scripts/publish/publish.sh      — publish only"

