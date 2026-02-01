#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[DEBUG]\033[0m $*"; }
section() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }

get_file_mtime() {
  local f="$1"
  # Cross-platform stat: Linux uses -c %y, macOS/BSD uses -f %Sm
  if stat -c %y "$f" >/dev/null 2>&1; then
    stat -c %y "$f" 2>/dev/null | cut -d' ' -f1-2 || echo "unknown"
  else
    stat -f %Sm "$f" 2>/dev/null || echo "unknown"
  fi
}

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
for dir in dist site/public releases .backups sync; do
  if [[ -d "$PROJECT_ROOT/$dir" ]]; then
    local size=$(du -sh "$PROJECT_ROOT/$dir" 2>/dev/null | cut -f1)
    log "✓ $dir/ ($size)"
  else
    log "✗ $dir/ (missing)"
  fi
done

section "APT Repository"
if [[ -d "$PROJECT_ROOT/site/public/apt" ]]; then
  log "Structure:"
  find "$PROJECT_ROOT/site/public/apt" -type f | head -20 | sed 's/^/  /'
  
  log ""
  log "Package count:"
  local deb_count=$(ls -1 "$PROJECT_ROOT/site/public/apt/pool/main"/*.deb 2>/dev/null | wc -l || echo "0")
  log "  DEB packages: $deb_count"
  
  if [[ -f "$PROJECT_ROOT/site/public/apt/dists/stable/Release" ]]; then
    log ""
    log "Release file:"
    head -5 "$PROJECT_ROOT/site/public/apt/dists/stable/Release" | sed 's/^/  /'
  fi
else
  log "APT repository not found"
fi

section "RPM Repository"
if [[ -d "$PROJECT_ROOT/site/public/rpm" ]]; then
  log "Structure:"
  find "$PROJECT_ROOT/site/public/rpm" -type f | head -20 | sed 's/^/  /'
  
  log ""
  log "Package count:"
  local rpm_x86=$(ls -1 "$PROJECT_ROOT/site/public/rpm/x86_64"/*.rpm 2>/dev/null | wc -l || echo "0")
  local rpm_arm=$(ls -1 "$PROJECT_ROOT/site/public/rpm/aarch64"/*.rpm 2>/dev/null | wc -l || echo "0")
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
if [[ -f "$PROJECT_ROOT/site/public/MANIFEST.txt" ]]; then
  log "✓ Manifest exists"
  log "Last updated: $(get_file_mtime "$PROJECT_ROOT/site/public/MANIFEST.txt")"
else
  log "✗ Manifest not found"
fi

section "Summary"
log "Debug information collected successfully"
log "For detailed documentation, see RELEASE_PROCESS.md"

