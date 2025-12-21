#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
DIST_DIR="${DIST_DIR:-dist}"
REPO_DIR="${REPO_DIR:-repo}"
APT_REPO_DIR="$REPO_DIR/apt"
RPM_REPO_DIR="$REPO_DIR/rpm"
BACKUP_DIR="${BACKUP_DIR:-.backups}"
LOCK_FILE="/tmp/helium-publish.lock"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[PUBLISH]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

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
  
  [[ -d "$DIST_DIR" ]] || err "Distribution directory not found: $DIST_DIR"
  
  local deb_count=0
  local rpm_count=0
  
  for deb in "$DIST_DIR"/*.deb 2>/dev/null || true; do
    [[ -f "$deb" ]] || continue
    if ! dpkg -I "$deb" >/dev/null 2>&1; then
      err "Invalid DEB package: $deb"
    fi
    ((deb_count++))
  done
  
  for rpm in "$DIST_DIR"/*.rpm 2>/dev/null || true; do
    [[ -f "$rpm" ]] || continue
    if ! rpm -K "$rpm" >/dev/null 2>&1 2>&1; then
      warn "Could not verify RPM: $rpm (rpm tool may not be available)"
    fi
    ((rpm_count++))
  done
  
  if [[ $deb_count -eq 0 && $rpm_count -eq 0 ]]; then
    err "No packages found in $DIST_DIR"
  fi
  
  log "Found $deb_count DEB and $rpm_count RPM packages"
}

backup_repos() {
  log "Creating backup of current repositories..."
  
  mkdir -p "$BACKUP_DIR"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="repo_backup_${timestamp}"
  
  if [[ -d "$APT_REPO_DIR" ]]; then
    tar -czf "$BACKUP_DIR/${backup_name}_apt.tar.gz" -C "$REPO_DIR" apt 2>/dev/null || true
    log "APT backup: $BACKUP_DIR/${backup_name}_apt.tar.gz"
  fi
  
  if [[ -d "$RPM_REPO_DIR" ]]; then
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
  for deb in "$DIST_DIR"/*.deb 2>/dev/null || true; do
    [[ -f "$deb" ]] || continue
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
  
  dpkg-scanpackages --arch amd64 pool/main > dists/stable/main/binary-amd64/Packages 2>/dev/null || true
  gzip -k -f dists/stable/main/binary-amd64/Packages 2>/dev/null || true
  
  dpkg-scanpackages --arch arm64 pool/main > dists/stable/main/binary-arm64/Packages 2>/dev/null || true
  gzip -k -f dists/stable/main/binary-arm64/Packages 2>/dev/null || true
  
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
  for rpm in "$DIST_DIR"/*.rpm 2>/dev/null || true; do
    [[ -f "$rpm" ]] || continue
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
    if [[ -n "$(ls -A $arch/*.rpm 2>/dev/null)" ]]; then
      log "Generating metadata for $arch..."
      if command -v createrepo_c >/dev/null 2>&1; then
        createrepo_c --update "$arch" 2>/dev/null || createrepo_c "$arch" 2>/dev/null || true
      else
        warn "createrepo_c not available, skipping RPM metadata generation"
      fi
    fi
  done
  
  cd - >/dev/null
  log "RPM repository updated successfully"
}

validate_repos() {
  log "Validating repositories..."
  
  # Check APT
  if [[ -d "$APT_REPO_DIR" ]]; then
    [[ -f "$APT_REPO_DIR/dists/stable/Release" ]] || err "APT Release file missing"
    [[ -f "$APT_REPO_DIR/dists/stable/main/binary-amd64/Packages" ]] || err "APT amd64 Packages missing"
    [[ -f "$APT_REPO_DIR/dists/stable/main/binary-arm64/Packages" ]] || err "APT arm64 Packages missing"
    log "APT repository structure: OK"
  fi
  
  # Check RPM
  if [[ -d "$RPM_REPO_DIR" ]]; then
    [[ -d "$RPM_REPO_DIR/x86_64" ]] || err "RPM x86_64 directory missing"
    [[ -d "$RPM_REPO_DIR/aarch64" ]] || err "RPM aarch64 directory missing"
    log "RPM repository structure: OK"
  fi
}

generate_manifest() {
  log "Generating manifest..."
  
  local manifest_file="$REPO_DIR/MANIFEST.txt"
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
  
  for deb in "$APT_REPO_DIR/pool/main"/*.deb 2>/dev/null || true; do
    [[ -f "$deb" ]] || continue
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
  
  for rpm in "$RPM_REPO_DIR"/*/*.rpm 2>/dev/null || true; do
    [[ -f "$rpm" ]] || continue
    local size=$(stat -c%s "$rpm" 2>/dev/null || stat -f%z "$rpm" 2>/dev/null || echo "0")
    local hash=$(sha256sum "$rpm" | cut -d' ' -f1)
    echo "  $(basename "$rpm") (size: $size, sha256: $hash)" >> "$manifest_file"
  done
  
  log "Manifest: $manifest_file"
}

# --- Main ---

check_deps
acquire_lock

log "Starting release publication process..."
log "Distribution directory: $DIST_DIR"
log "Repository directory: $REPO_DIR"

validate_packages
backup_repos
publish_apt
publish_rpm
validate_repos
generate_manifest

log "Release publication completed successfully!"
log ""
log "Next steps:"
log "  1. Review changes: git diff repo/"
log "  2. Commit: git add repo/ && git commit -m 'chore: update repositories'"
log "  3. Push: git push"

