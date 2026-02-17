#!/usr/bin/env bash
# ==============================================================================
# Helium Browser — One-liner installer for Debian / Ubuntu / Mint
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
# ==============================================================================
set -euo pipefail

# ── Colours (auto-detect terminal) ───────────────────────────────────────────
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_RED='\033[0;31m'
  C_BLUE='\033[0;34m'  C_RESET='\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_BLUE='' C_RESET=''
fi

log()  { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; exit 1; }

# ── Privilege handling ───────────────────────────────────────────────────────
SUDO=""
(( EUID != 0 )) && SUDO="sudo"

# ── Architecture ─────────────────────────────────────────────────────────────
ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
log "Architecture: $ARCH"

command -v apt-get >/dev/null 2>&1 || err "apt-get not found. This script is for Debian/Ubuntu systems."

# ── Configuration ────────────────────────────────────────────────────────────
readonly REPO_URL="https://arvaidasre.github.io/helium-browser-deb/apt"
readonly LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"

# ── Install / Update ────────────────────────────────────────────────────────
if dpkg -l helium-browser 2>/dev/null | grep -q '^ii'; then
  current="$(dpkg -l helium-browser | awk '/^ii/{print $3}')"
  log "Already installed (version: $current) — updating..."
else
  log "Installing Helium Browser..."
fi

# Clean old source entry
[[ -f "$LIST_FILE" ]] && $SUDO rm -f "$LIST_FILE"

log "Adding repository..."
echo "deb [arch=$ARCH trusted=yes] $REPO_URL stable main" | $SUDO tee "$LIST_FILE" >/dev/null

log "Updating package list..."
$SUDO apt-get update -qq

log "Installing helium-browser..."
$SUDO apt-get install -y helium-browser

# ── Verify ───────────────────────────────────────────────────────────────────
if command -v helium >/dev/null 2>&1; then
  log "Helium Browser installed successfully!"
  echo ""
  echo -e "${C_BLUE}Launch:${C_RESET} run 'helium' or use your applications menu."
else
  warn "'helium' command not in PATH — try /usr/bin/helium or restart your terminal."
fi
