#!/usr/bin/env bash
# ==============================================================================
# Helium Browser — One-liner installer for Fedora / RHEL / CentOS
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
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
readonly KEY_URL="$REPO_URL/rpm/RPM-GPG-KEY-helium"
readonly REPO_FILE="/etc/yum.repos.d/helium.repo"

# ── Detect package manager ───────────────────────────────────────────────────
if command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG_MGR="yum"
else
  err "Neither dnf nor yum found. This script is for Fedora/RHEL systems."
fi

# ── Detect architecture ──────────────────────────────────────────────────────
readonly ARCH="$(uname -m)"

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${C_CYAN}╭─────────────────────────────────────────────────╮${C_RESET}"
echo -e "${C_CYAN}│${C_RESET}     Helium Browser for Linux - Installer      ${C_CYAN}│${C_RESET}"
echo -e "${C_CYAN}╰─────────────────────────────────────────────────╯${C_RESET}"
echo ""

log "Detected architecture: $ARCH"
log "Package manager: $PKG_MGR"

# ── Check dependencies ───────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || err "curl is required but not installed."

# ── Check if already installed ───────────────────────────────────────────────
if rpm -q helium-browser >/dev/null 2>&1; then
  current="$(rpm -q helium-browser)"
  log "Already installed ($current) — updating..."
else
  log "Installing Helium Browser..."
fi

# ── Import GPG key ───────────────────────────────────────────────────────────
log "Importing GPG key..."
if $SUDO rpm --import "$KEY_URL" 2>/dev/null; then
  log "GPG key imported successfully"
else
  warn "Could not import GPG key. Continuing without key verification."
fi

# ── Add repository ───────────────────────────────────────────────────────────
log "Adding repository..."

$SUDO tee "$REPO_FILE" > /dev/null <<EOF
[helium]
name=Helium Browser
baseurl=$REPO_URL/rpm/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$KEY_URL
EOF

# ── Install ──────────────────────────────────────────────────────────────────
log "Installing helium-browser..."
$SUDO $PKG_MGR install -y helium-browser

# ── Verify installation ──────────────────────────────────────────────────────
echo ""
if command -v helium >/dev/null 2>&1; then
  echo -e "${C_GREEN}✓ Helium Browser installed successfully!${C_RESET}"
  echo ""
  echo -e "${C_BLUE}Launch:${C_RESET} Type 'helium' in terminal or find it in your applications menu."
  echo ""
  echo -e "${C_CYAN}Repository:${C_RESET} $REPO_FILE"
else
  warn "'helium' command not in PATH — try /usr/bin/helium or restart your terminal."
fi
