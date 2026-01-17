#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[DEBUG]\033[0m $*"; }
section() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }

# --- Main ---

section "System Information"
log "OS: $(uname -s)"
log "Architecture: $(uname -m)"
log "Kernel: $(uname -r)"
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  log "Distribution: $PRETTY_NAME"
fi

section "Disk Space"
df -h | grep -E "^/dev|^Filesystem"

section "Dependencies"
for cmd in curl jq git dpkg-scanpackages gzip createrepo_c fpm sha256sum; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "✓ $cmd: $(command -v "$cmd")"
  else
    log "✗ $cmd: NOT FOUND"
  fi
done

section "Directory Structure"
for dir in dist repo releases .backups sync; do
  if [[ -d "$PROJECT_ROOT/$dir" ]]; then
    local size=$(du -sh "$PROJECT_ROOT/$dir" 2>/dev/null | cut -f1)
    log "✓ $dir/ ($size)"
  else
    log "✗ $dir/ (missing)"
  fi
done

section "APT Repository"
if [[ -d "$PROJECT_ROOT/repo/apt" ]]; then
  log "Structure:"
  find "$PROJECT_ROOT/repo/apt" -type f | head -20 | sed 's/^/  /'
  
  log ""
  log "Package count:"
  local deb_count=$(ls -1 "$PROJECT_ROOT/repo/apt/pool/main"/*.deb 2>/dev/null | wc -l || echo "0")
  log "  DEB packages: $deb_count"
  
  if [[ -f "$PROJECT_ROOT/repo/apt/dists/stable/Release" ]]; then
    log ""
    log "Release file:"
    head -5 "$PROJECT_ROOT/repo/apt/dists/stable/Release" | sed 's/^/  /'
  fi
else
  log "APT repository not found"
fi

section "RPM Repository"
if [[ -d "$PROJECT_ROOT/repo/rpm" ]]; then
  log "Structure:"
  find "$PROJECT_ROOT/repo/rpm" -type f | head -20 | sed 's/^/  /'
  
  log ""
  log "Package count:"
  local rpm_x86=$(ls -1 "$PROJECT_ROOT/repo/rpm/x86_64"/*.rpm 2>/dev/null | wc -l || echo "0")
  local rpm_arm=$(ls -1 "$PROJECT_ROOT/repo/rpm/aarch64"/*.rpm 2>/dev/null | wc -l || echo "0")
  log "  x86_64 packages: $rpm_x86"
  log "  aarch64 packages: $rpm_arm"
else
  log "RPM repository not found"
fi

section "Built Packages"
if [[ -d "$PROJECT_ROOT/dist" ]]; then
  local pkg_count=$(ls -1 "$PROJECT_ROOT/dist"/*.{deb,rpm} 2>/dev/null | wc -l || echo "0")
  if [[ $pkg_count -gt 0 ]]; then
    log "Found $pkg_count packages:"
    ls -lh "$PROJECT_ROOT/dist"/*.{deb,rpm} 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || true
  else
    log "No packages found"
  fi
else
  log "dist/ directory not found"
fi

section "Synced Releases"
if [[ -d "$PROJECT_ROOT/releases" ]]; then
  local release_count=$(ls -d "$PROJECT_ROOT/releases"/*/ 2>/dev/null | wc -l || echo "0")
  log "Found $release_count releases"
  
  if [[ -f "$PROJECT_ROOT/releases/INDEX.md" ]]; then
    log "✓ INDEX.md exists"
  fi
  
  if [[ -f "$PROJECT_ROOT/releases/CHANGELOG.md" ]]; then
    local lines=$(wc -l < "$PROJECT_ROOT/releases/CHANGELOG.md")
    log "✓ CHANGELOG.md exists ($lines lines)"
  fi
else
  log "releases/ directory not found"
fi

section "Git Status"
if [[ -d "$PROJECT_ROOT/.git" ]]; then
  log "Repository: $(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
  log "Branch: $(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  log "Commit: $(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
  
  log ""
  log "Tags:"
  git -C "$PROJECT_ROOT" tag -l | head -10 | sed 's/^/  /'
  
  log ""
  log "Uncommitted changes:"
  local changes=$(git -C "$PROJECT_ROOT" status --porcelain | wc -l)
  log "  $changes files"
else
  log "Not a git repository"
fi

section "Recent Backups"
if [[ -d "$PROJECT_ROOT/.backups" ]]; then
  local backup_count=$(ls -1 "$PROJECT_ROOT/.backups"/*.tar.gz 2>/dev/null | wc -l || echo "0")
  if [[ $backup_count -gt 0 ]]; then
    log "Found $backup_count backups:"
    ls -lh "$PROJECT_ROOT/.backups"/*.tar.gz 2>/dev/null | tail -5 | awk '{print "  " $9 " (" $5 ")"}' || true
  else
    log "No backups found"
  fi
else
  log ".backups/ directory not found"
fi

section "Manifest"
if [[ -f "$PROJECT_ROOT/repo/MANIFEST.txt" ]]; then
  log "✓ Manifest exists"
  log "Last updated: $(stat -c %y "$PROJECT_ROOT/repo/MANIFEST.txt" 2>/dev/null | cut -d' ' -f1-2 || stat -f %Sm "$PROJECT_ROOT/repo/MANIFEST.txt" 2>/dev/null || echo "unknown")"
else
  log "✗ Manifest not found"
fi

section "Summary"
log "Debug information collected successfully"
log "For detailed documentation, see RELEASE_PROCESS.md"

