#!/usr/bin/env bash
# ==============================================================================
# Helium Browser — One-liner installer for Debian / Ubuntu / Mint
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
# ==============================================================================
set -euo pipefail

# ── Colours (auto-detect terminal) ───────────────────────────────────────────
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_RED='\033[0;31m'
  C_BLUE='\033[0;34m'  C_CYAN='\033[0;36m' C_RESET='\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_BLUE='' C_CYAN='' C_RESET=''
fi

log()  { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; exit 1; }

# ── Privilege handling ───────────────────────────────────────────────────────
SUDO=""
(( EUID != 0 )) && SUDO="sudo"

# ── Configuration ────────────────────────────────────────────────────────────
readonly REPO_URL="https://arvaidasre.github.io/helium-browser-deb"
readonly KEY_URL="$REPO_URL/apt/HELIUM-GPG-KEY"
readonly KEYRING="/usr/share/keyrings/helium.gpg"
readonly LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"

# ── Detect architecture ──────────────────────────────────────────────────────
detect_arch() {
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
  elif [[ "$(uname -m)" == "aarch64" ]]; then
    echo "arm64"
  else
    echo "amd64"
  fi
}

readonly ARCH="$(detect_arch)"

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${C_CYAN}╭─────────────────────────────────────────────────╮${C_RESET}"
echo -e "${C_CYAN}│${C_RESET}     Helium Browser for Linux - Installer      ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╰─────────────────────────────────────────────────╯${C_RESET}"
echo ""

log "Detected architecture: $ARCH"

# ── Check dependencies ───────────────────────────────────────────────────────
command -v apt-get >/dev/null 2>&1 || err "apt-get not found. This script is for Debian/Ubuntu systems."
command -v curl >/dev/null 2>&1 || err "curl is required but not installed."

# ── Check if already installed ───────────────────────────────────────────────
if dpkg -l helium-browser 2>/dev/null | grep -q '^ii'; then
  current="$(dpkg -l helium-browser | awk '/^ii/{print $3}')"
  log "Already installed (version: $current) — updating..."
else
  log "Installing Helium Browser..."
fi

# ── Import GPG key ───────────────────────────────────────────────────────────
log "Importing GPG key..."
if curl -fsSL "$KEY_URL" 2>/dev/null | $SUDO gpg --dearmor -o "$KEYRING" 2>/dev/null; then
  log "GPG key imported successfully"
else
  warn "Could not import GPG key. Will use trusted=yes fallback."
fi

# ── Add repository ───────────────────────────────────────────────────────────
log "Adding repository..."

# Remove old repository file if exists (without keyring)
[[ -f "$LIST_FILE" ]] && $SUDO rm -f "$LIST_FILE"

# Add repository with signed-by if key exists
if [[ -f "$KEYRING" ]]; then
  echo "deb [arch=$ARCH signed-by=$KEYRING] $REPO_URL/apt stable main" | $SUDO tee "$LIST_FILE" >/dev/null
else
  # Fallback to trusted=yes for compatibility
  echo "deb [arch=$ARCH trusted=yes] $REPO_URL/apt stable main" | $SUDO tee "$LIST_FILE" >/dev/null
fi

# ── Update and install ───────────────────────────────────────────────────────
log "Updating package list..."
$SUDO apt-get update -qq

log "Installing helium-browser..."
$SUDO apt-get install -y helium-browser

# ── Verify installation ──────────────────────────────────────────────────────
echo ""
if command -v helium >/dev/null 2>&1; then
  echo -e "${C_GREEN}✓ Helium Browser installed successfully!${C_RESET}"
  echo ""
  echo -e "${C_BLUE}Launch:${C_RESET} Type 'helium' in terminal or find it in your applications menu."
  echo ""
  echo -e "${C_CYAN}Repository:${C_RESET} $REPO_URL"
  echo -e "${C_CYAN}GPG Key:${C_RESET} $KEYRING"
else
  warn "'helium' command not in PATH — try /usr/bin/helium or restart your terminal."
fi
