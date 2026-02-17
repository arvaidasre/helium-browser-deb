#!/usr/bin/env bash
# ==============================================================================
# debug.sh — Collect system, repo, and build diagnostics
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="DEBUG"

# ── System info ──────────────────────────────────────────────────────────────

section "System Information"
log "OS: $(uname -s)"
log "Architecture: $(uname -m)"
log "Kernel: $(uname -r)"
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  log "Distribution: $PRETTY_NAME"
fi

section "Disk Space"
df -h | grep -E "^/dev|^Filesystem"

# ── Dependencies ─────────────────────────────────────────────────────────────

section "Dependencies"
for cmd in curl jq git dpkg-scanpackages gzip createrepo_c fpm sha256sum; do
  if command -v "$cmd" >/dev/null 2>&1; then
    log "[OK] $cmd: $(command -v "$cmd")"
  else
    log "[MISSING] $cmd"
  fi
done

# ── Project directories ─────────────────────────────────────────────────────

section "Directory Structure"
for dir in dist site/public releases .backups sync; do
  if [[ -d "$HELIUM_PROJECT_ROOT/$dir" ]]; then
    dir_size="$(du -sh "$HELIUM_PROJECT_ROOT/$dir" 2>/dev/null | cut -f1)"
    log "[OK] $dir/ ($dir_size)"
  else
    log "[MISSING] $dir/"
  fi
done

# ── APT Repository ──────────────────────────────────────────────────────────

section "APT Repository"
APT_ROOT="$HELIUM_PROJECT_ROOT/site/public/apt"
if [[ -d "$APT_ROOT" ]]; then
  log "Structure:"
  find "$APT_ROOT" -type f | head -20 | sed 's/^/  /'

  deb_count="$(find "$APT_ROOT/pool/main" -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)"
  log "DEB packages: $deb_count"

  if [[ -f "$APT_ROOT/dists/stable/Release" ]]; then
    log "Release file (first 5 lines):"
    head -5 "$APT_ROOT/dists/stable/Release" | sed 's/^/  /'
  fi
else
  log "APT repository not found"
fi

# ── RPM Repository ──────────────────────────────────────────────────────────

section "RPM Repository"
RPM_ROOT="$HELIUM_PROJECT_ROOT/site/public/rpm"
if [[ -d "$RPM_ROOT" ]]; then
  log "Structure:"
  find "$RPM_ROOT" -type f | head -20 | sed 's/^/  /'

  rpm_x86="$(find "$RPM_ROOT/x86_64" -maxdepth 1 -name '*.rpm' 2>/dev/null | wc -l)"
  rpm_arm="$(find "$RPM_ROOT/aarch64" -maxdepth 1 -name '*.rpm' 2>/dev/null | wc -l)"
  log "x86_64 packages: $rpm_x86"
  log "aarch64 packages: $rpm_arm"
else
  log "RPM repository not found"
fi

# ── Built packages ──────────────────────────────────────────────────────────

section "Built Packages"
DIST="$HELIUM_PROJECT_ROOT/dist"
if [[ -d "$DIST" ]]; then
  shopt -s nullglob
  pkgs=("$DIST"/*.deb "$DIST"/*.rpm)
  shopt -u nullglob
  if (( ${#pkgs[@]} )); then
    log "Found ${#pkgs[@]} packages:"
    ls -lh "${pkgs[@]}" | awk '{print "  " $9 " (" $5 ")"}' || true
  else
    log "No packages found"
  fi
else
  log "dist/ directory not found"
fi

# ── Synced releases ─────────────────────────────────────────────────────────

section "Synced Releases"
REL_DIR="$HELIUM_PROJECT_ROOT/releases"
if [[ -d "$REL_DIR" ]]; then
  release_count="$(find "$REL_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  log "Found $release_count releases"
  [[ -f "$REL_DIR/INDEX.md" ]]     && log "[OK] INDEX.md"
  [[ -f "$REL_DIR/CHANGELOG.md" ]] && log "[OK] CHANGELOG.md ($(wc -l < "$REL_DIR/CHANGELOG.md") lines)"
else
  log "releases/ directory not found"
fi

# ── Git status ───────────────────────────────────────────────────────────────

section "Git Status"
if [[ -d "$HELIUM_PROJECT_ROOT/.git" ]]; then
  log "Branch: $(git -C "$HELIUM_PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  log "Commit: $(git -C "$HELIUM_PROJECT_ROOT" rev-parse --short HEAD)"
  log "Tags:"
  git -C "$HELIUM_PROJECT_ROOT" tag -l | head -10 | sed 's/^/  /'
  changes="$(git -C "$HELIUM_PROJECT_ROOT" status --porcelain | wc -l)"
  log "Uncommitted changes: $changes files"
else
  log "Not a git repository"
fi

# ── Backups & manifest ───────────────────────────────────────────────────────

section "Backups"
BACKUPS="$HELIUM_PROJECT_ROOT/.backups"
if [[ -d "$BACKUPS" ]]; then
  shopt -s nullglob
  bk=("$BACKUPS"/*.tar.gz)
  shopt -u nullglob
  if (( ${#bk[@]} )); then
    log "Found ${#bk[@]} backups:"
    ls -lh "${bk[@]}" | tail -5 | awk '{print "  " $9 " (" $5 ")"}' || true
  else
    log "No backups found"
  fi
else
  log ".backups/ directory not found"
fi

section "Manifest"
MANIFEST="$HELIUM_PROJECT_ROOT/site/public/MANIFEST.txt"
if [[ -f "$MANIFEST" ]]; then
  log "[OK] Manifest exists — last modified: $(file_mtime "$MANIFEST")"
else
  log "[MISSING] Manifest not found"
fi

section "Done"
log "Debug information collected."

