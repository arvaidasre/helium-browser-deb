#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
DIST_DIR="${DIST_DIR:-dist}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_DIR="${REPO_DIR:-$PROJECT_ROOT/site/public}"
STAGING_DIR="${STAGING_DIR:-$PROJECT_ROOT/site/public.tmp}"
CURRENT_DIR="${CURRENT_DIR:-$PROJECT_ROOT/site/public.current}"
APT_REPO_DIR="$STAGING_DIR/apt"
RPM_REPO_DIR="$STAGING_DIR/rpm"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/.backups}"
LOCK_FILE="/tmp/helium-publish.lock"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[PUBLISH]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

die_with_restore() {
  warn "Publish failed - restoring previous repo state"
  if [[ -d "$CURRENT_DIR" ]]; then
    rm -rf "$REPO_DIR"
    mv "$CURRENT_DIR" "$REPO_DIR"
  fi
  exit 1
}

check_deps() {
  local deps=(dpkg-scanpackages gzip createrepo_c sha256sum)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "Missing optional dependency: $cmd"
    fi
  done
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    err "Another publish operation is in progress (lock file: $LOCK_FILE)"
  fi
  touch "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

validate_packages() {
  log "Validating packages in $DIST_DIR..."
  set -x
  
  [[ -d "$DIST_DIR" ]] || err "Distribution directory not found: $DIST_DIR"
  
  local deb_count=0
  local rpm_count=0
  local has_deb_amd64=false
  local has_deb_arm64=false
  local has_rpm_x86=false
  local has_rpm_arm=false
  
  local debs
  local rpms
  debs=$(ls -1 "$DIST_DIR"/*.deb 2>/dev/null || true)
  rpms=$(ls -1 "$DIST_DIR"/*.rpm 2>/dev/null || true)

  for deb in $debs; do
    if ! dpkg -I "$deb" >/dev/null 2>&1; then
      err "Invalid DEB package: $deb"
    fi
    ((++deb_count))
    local name
    name=$(basename "$deb")
    name=${name,,}
    if [[ "$name" == *amd64* || "$name" == *x86_64* ]]; then
      has_deb_amd64=true
    fi
    if [[ "$name" == *arm64* || "$name" == *aarch64* ]]; then
      has_deb_arm64=true
    fi
  done

  for rpm in $rpms; do
    if command -v rpm >/dev/null 2>&1; then
      if ! rpm -K "$rpm" >/dev/null 2>&1; then
        warn "Could not verify RPM: $rpm"
      fi
    fi
    ((++rpm_count))
    local name
    name=$(basename "$rpm")
    name=${name,,}
    if [[ "$name" == *x86_64* || "$name" == *amd64* ]]; then
      has_rpm_x86=true
    fi
    if [[ "$name" == *aarch64* || "$name" == *arm64* ]]; then
      has_rpm_arm=true
    fi
  done
  
  if [[ $deb_count -eq 0 && $rpm_count -eq 0 ]]; then
    err "No packages found in $DIST_DIR"
  fi

  if [[ "$has_deb_amd64" != "true" ]]; then
    err "Missing amd64 .deb package in $DIST_DIR"
  fi

  if [[ "$has_deb_arm64" != "true" ]]; then
    err "Missing arm64 .deb package in $DIST_DIR"
  fi

  if [[ "$has_rpm_x86" != "true" ]]; then
    err "Missing x86_64 .rpm package in $DIST_DIR"
  fi

  if [[ "$has_rpm_arm" != "true" ]]; then
    err "Missing aarch64 .rpm package in $DIST_DIR"
  fi
  
  log "Found $deb_count DEB and $rpm_count RPM packages"
  set +x
}

backup_repos() {
  log "Creating backup of current repositories..."
  
  mkdir -p "$BACKUP_DIR"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="repo_backup_${timestamp}"
  
  if [[ -d "$REPO_DIR/apt" ]]; then
    tar -czf "$BACKUP_DIR/${backup_name}_apt.tar.gz" -C "$REPO_DIR" apt 2>/dev/null || true
    log "APT backup: $BACKUP_DIR/${backup_name}_apt.tar.gz"
  fi
  
  if [[ -d "$REPO_DIR/rpm" ]]; then
    tar -czf "$BACKUP_DIR/${backup_name}_rpm.tar.gz" -C "$REPO_DIR" rpm 2>/dev/null || true
    log "RPM backup: $BACKUP_DIR/${backup_name}_rpm.tar.gz"
  fi
}

publish_apt() {
  log "Publishing APT repository..."
  
  mkdir -p "$APT_REPO_DIR/pool/main"
  mkdir -p "$APT_REPO_DIR/dists/stable/main/binary-amd64"
  mkdir -p "$APT_REPO_DIR/dists/stable/main/binary-arm64"
  
  # Copy new packages
  local debs
  debs=$(ls -1 "$DIST_DIR"/*.deb 2>/dev/null || true)

  for deb in $debs; do
    local basename=$(basename "$deb")
    
    # Check if package already exists
    if [[ -f "$APT_REPO_DIR/pool/main/$basename" ]]; then
      local new_hash=$(sha256sum "$deb" | cut -d' ' -f1)
      local old_hash=$(sha256sum "$APT_REPO_DIR/pool/main/$basename" | cut -d' ' -f1)
      
      if [[ "$new_hash" == "$old_hash" ]]; then
        log "Package already in repository (unchanged): $basename"
        continue
      else
        log "Replacing package: $basename"
      fi
    fi
    
    cp "$deb" "$APT_REPO_DIR/pool/main/"
    log "Added: $basename"
  done
  
  # Generate Packages files
  cd "$APT_REPO_DIR"
  
  log "Generating Packages files (with architecture filtering)..."

  # For amd64
  dpkg-scanpackages pool/main 2>/dev/null | awk -v RS='' -v ORS='\n\n' '/Architecture: (amd64|x86_64)/' > dists/stable/main/binary-amd64/Packages
  if [[ -s dists/stable/main/binary-amd64/Packages ]]; then
    gzip -k -f dists/stable/main/binary-amd64/Packages 2>/dev/null || err "Failed to gzip amd64 Packages"
  else
    err "No amd64 packages found in pool/main"
  fi
  
  # For arm64
  dpkg-scanpackages pool/main 2>/dev/null | awk -v RS='' -v ORS='\n\n' '/Architecture: (arm64|aarch64)/' > dists/stable/main/binary-arm64/Packages
  if [[ -s dists/stable/main/binary-arm64/Packages ]]; then
    gzip -k -f dists/stable/main/binary-arm64/Packages 2>/dev/null || err "Failed to gzip arm64 Packages"
  else
    err "No arm64 packages found in pool/main"
  fi
  
  # Generate Release file
  local release_date=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S %Z")
  cat > dists/stable/Release <<EOF
Origin: $PACKAGE_NAME
Label: $PACKAGE_NAME
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Helium Browser Repository
Date: $release_date
EOF
  
  # Add checksums
  {
    echo "MD5Sum:"
    for f in dists/stable/main/binary-*/Packages*; do
      [[ -f "$f" ]] || continue
      local size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
      local hash=$(md5sum "$f" | cut -d' ' -f1)
      local rel_path="${f#dists/stable/}"
      printf " %s %8s %s\n" "$hash" "$size" "$rel_path"
    done
    echo "SHA256:"
    for f in dists/stable/main/binary-*/Packages*; do
      [[ -f "$f" ]] || continue
      local size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0")
      local hash=$(sha256sum "$f" | cut -d' ' -f1)
      local rel_path="${f#dists/stable/}"
      printf " %s %8s %s\n" "$hash" "$size" "$rel_path"
    done
  } >> dists/stable/Release
  
  # Create distribution aliases
  for dist in noble jammy focal bookworm bullseye; do
    rm -rf "dists/$dist"
    mkdir -p "dists/$dist"
    cp -a dists/stable/* "dists/$dist/"
    
    if [[ -f "dists/$dist/Release" ]]; then
      sed -i \
        -e "s/^Suite: .*/Suite: $dist/" \
        -e "s/^Codename: .*/Codename: $dist/" \
        "dists/$dist/Release"
    fi
  done
  
  cd - >/dev/null
  log "APT repository updated successfully"
}

publish_rpm() {
  log "Publishing RPM repository..."
  
  mkdir -p "$RPM_REPO_DIR/x86_64"
  mkdir -p "$RPM_REPO_DIR/aarch64"
  
  # Copy new packages
  local rpms
  rpms=$(ls -1 "$DIST_DIR"/*.rpm 2>/dev/null || true)

  for rpm in $rpms; do
    local basename=$(basename "$rpm")
    local arch="x86_64"
    
    if [[ "$rpm" == *"aarch64"* ]] || [[ "$rpm" == *"arm64"* ]]; then
      arch="aarch64"
    fi
    
    # Check if package already exists
    if [[ -f "$RPM_REPO_DIR/$arch/$basename" ]]; then
      local new_hash=$(sha256sum "$rpm" | cut -d' ' -f1)
      local old_hash=$(sha256sum "$RPM_REPO_DIR/$arch/$basename" | cut -d' ' -f1)
      
      if [[ "$new_hash" == "$old_hash" ]]; then
        log "Package already in repository (unchanged): $basename"
        continue
      else
        log "Replacing package: $basename"
      fi
    fi
    
    cp "$rpm" "$RPM_REPO_DIR/$arch/"
    log "Added: $basename (arch: $arch)"
  done
  
  # Generate repository metadata
  cd "$RPM_REPO_DIR"
  
  for arch in x86_64 aarch64; do
    if compgen -G "$arch/*.rpm" >/dev/null; then
      log "Generating metadata for $arch..."
      if command -v createrepo_c >/dev/null 2>&1; then
        createrepo_c --update "$arch" 2>/dev/null || createrepo_c "$arch" 2>/dev/null || true
      else
        warn "createrepo_c not available, skipping RPM metadata generation"
      fi
    else
      err "No RPM packages found for $arch in dist/"
    fi
  done
  
  cd - >/dev/null
  log "RPM repository updated successfully"
}


generate_manifest() {
  log "Generating manifest..."
  
  local manifest_file="$STAGING_DIR/MANIFEST.txt"
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  
  cat > "$manifest_file" <<EOF
Helium Browser Repository Manifest
Generated: $timestamp

=== APT Repository ===
Location: $APT_REPO_DIR
Distributions: stable, noble, jammy, focal, bookworm, bullseye
Architectures: amd64, arm64

Packages:
EOF
  
  shopt -s nullglob
  local debs=("$APT_REPO_DIR/pool/main"/*.deb)
  shopt -u nullglob
  for deb in "${debs[@]}"; do
    local size=$(stat -c%s "$deb" 2>/dev/null || stat -f%z "$deb" 2>/dev/null || echo "0")
    local hash=$(sha256sum "$deb" | cut -d' ' -f1)
    echo "  $(basename "$deb") (size: $size, sha256: $hash)" >> "$manifest_file"
  done
  
  cat >> "$manifest_file" <<EOF

=== RPM Repository ===
Location: $RPM_REPO_DIR
Architectures: x86_64, aarch64

Packages:
EOF
  
  shopt -s nullglob
  local rpms=("$RPM_REPO_DIR"/*/*.rpm)
  shopt -u nullglob
  for rpm in "${rpms[@]}"; do
    local size=$(stat -c%s "$rpm" 2>/dev/null || stat -f%z "$rpm" 2>/dev/null || echo "0")
    local hash=$(sha256sum "$rpm" | cut -d' ' -f1)
    echo "  $(basename "$rpm") (size: $size, sha256: $hash)" >> "$manifest_file"
  done
  
  log "Manifest: $manifest_file"
}

# --- Main ---

check_deps
acquire_lock

trap 'die_with_restore' ERR

log "Starting release publication process..."
log "Distribution directory: $DIST_DIR"
log "Repository directory: $REPO_DIR"
log "Staging directory: $STAGING_DIR"
log "Current directory: $CURRENT_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp "$PROJECT_ROOT/site/install.sh" "$STAGING_DIR/install.sh"
cp "$PROJECT_ROOT/site/install-rpm.sh" "$STAGING_DIR/install-rpm.sh"

validate_packages
backup_repos
publish_apt
publish_rpm

cp "$STAGING_DIR/install.sh" "$APT_REPO_DIR/install.sh"
cp "$STAGING_DIR/install-rpm.sh" "$RPM_REPO_DIR/install-rpm.sh"

cp "$PROJECT_ROOT/site/index.html.template" "$STAGING_DIR/index.html"

generate_manifest

"$PROJECT_ROOT/scripts/utils/validate.sh" "$APT_REPO_DIR" "$RPM_REPO_DIR" "$STAGING_DIR"

rm -rf "$CURRENT_DIR"
if [[ -d "$REPO_DIR" ]]; then
  mv "$REPO_DIR" "$CURRENT_DIR"
fi
mv "$STAGING_DIR" "$REPO_DIR"
rm -rf "$CURRENT_DIR"

log "Release publication completed successfully!"
log ""
log "Next steps:"
log "  1. Review changes: git diff site/public/"
log "  2. Commit: git add site/public/ && git commit -m 'chore: update repositories'"
log "  3. Push: git push"

