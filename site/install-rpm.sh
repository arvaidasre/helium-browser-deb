#!/usr/bin/env bash
# ==============================================================================
# Helium Browser — One-liner installer for Fedora / RHEL / CentOS
# Usage: curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
# ==============================================================================
set -euo pipefail

# ── Colours (auto-detect terminal) ───────────────────────────────────────────
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_RED='\033[0;31m' C_RESET='\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

log()  { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; exit 1; }

# ── Architecture ─────────────────────────────────────────────────────────────
case "$(uname -m)" in
  x86_64)  REPO_ARCH="x86_64"  ;;
  aarch64) REPO_ARCH="aarch64" ;;
  arm64)   REPO_ARCH="aarch64" ;;
  *)       err "Unsupported architecture: $(uname -m)" ;;
esac

log "Architecture: $REPO_ARCH"

# ── Add repository ──────────────────────────────────────────────────────────
log "Adding Helium Browser repository..."
sudo tee /etc/yum.repos.d/helium.repo >/dev/null <<'EOF'
[helium]
name=Helium Browser Repository
baseurl=https://arvaidasre.github.io/helium-browser-deb/rpm/$basearch
enabled=1
gpgcheck=0
metadata_expire=1h
EOF

# ── Install ──────────────────────────────────────────────────────────────────
if command -v dnf >/dev/null 2>&1; then
  log "Installing with DNF..."
  sudo dnf install -y helium-browser
elif command -v yum >/dev/null 2>&1; then
  log "Installing with YUM..."
  sudo yum install -y helium-browser
else
  err "Neither DNF nor YUM found. Install manually."
fi

log "Helium Browser installed successfully!"
log "Launch: run 'helium' or use your applications menu."
