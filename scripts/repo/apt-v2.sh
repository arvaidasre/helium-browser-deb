#!/usr/bin/env bash
# ==============================================================================
# apt-v2.sh — Generate signed APT repository
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="APT-v2"

readonly REPO_DIR="${1:-site/public/apt}"
readonly APT_DISTS_DEFAULT=(stable noble jammy focal bookworm bullseye)
readonly CHANNEL="${CHANNEL:-stable}"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps dpkg-scanpackages gzip gpg

# ── GPG Setup ─────────────────────────────────────────────────────────────────

get_gpg_key_id() {
  gpg --list-secret-keys --keyid-format LONG 2>/dev/null | \
    grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2 || true
}

# ── Directory structure ───────────────────────────────────────────────────────

setup_repo_dirs() {
  log "Setting up APT repository in $REPO_DIR..."
  
  mkdir -p "$REPO_DIR/pool/main" \
           "$REPO_DIR/dists/stable/main/binary-amd64" \
           "$REPO_DIR/dists/stable/main/binary-arm64"
}

# ── Copy packages ─────────────────────────────────────────────────────────────

copy_packages() {
  [[ -d "dist" ]] || err "dist/ directory not found."
  
  log "Copying .deb packages to pool..."
  for deb in dist/*.deb; do
    [[ -f "$deb" ]] || continue
    cp "$deb" "$REPO_DIR/pool/main/"
  done
  
  # Verify both architectures exist
  ls -A "$REPO_DIR/pool/main"/*amd64*.deb >/dev/null 2>&1 || \
    err "No amd64 packages found!"
  ls -A "$REPO_DIR/pool/main"/*arm64*.deb >/dev/null 2>&1 || \
    err "No arm64 packages found!"
}

# ── Generate Packages files ───────────────────────────────────────────────────

generate_packages() {
  cd "$REPO_DIR"
  
  for arch_pair in "amd64:amd64|x86_64" "arm64:arm64|aarch64"; do
    arch="${arch_pair%%:*}"
    pattern="${arch_pair#*:}"
    
    log "Generating Packages for $arch..."
    
    dpkg-scanpackages --multiversion pool/main 2>/dev/null | \
      awk -v RS='' -v ORS='\n\n' "\$0 ~ /^Package:/ \u0026\u0026 /Architecture: ($pattern)/" > \
      "dists/stable/main/binary-$arch/Packages"
    
    if [[ -s "dists/stable/main/binary-$arch/Packages" ]]; then
      # Compress
      gzip -k -f "dists/stable/main/binary-$arch/Packages"
      # Generate hashes
      md5_packages[$arch]=$(md5sum "dists/stable/main/binary-$arch/Packages" | cut -d' ' -f1)
      sha256_packages[$arch]=$(sha256sum "dists/stable/main/binary-$arch/Packages" | cut -d' ' -f1)
      size_packages[$arch]=$(stat -c%s "dists/stable/main/binary-$arch/Packages")
    else
      err "No $arch packages found!"
    fi
  done
}

# ── Generate signed Release file ─────────────────────────────────────────────-

generate_signed_release() {
  cd "$REPO_DIR"
  
  local release_date
  release_date=$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S %Z')
  
  log "Generating Release file..."
  
  cat > "dists/stable/Release" <<RELEASE
Origin: Helium Browser Repository
Label: Helium Browser
Suite: stable
Codename: stable
Version: 1.0
Architectures: amd64 arm64
Components: main
Description: Helium Browser APT Repository
Date: $release_date
RELEASE

  # Add MD5Sum section
  {
    echo "MD5Sum:"
    for f in dists/stable/main/binary-*/Packages{,.gz}; do
      [[ -f "$f" ]] || continue
      printf " %s %16d %s\n" \
        "$(md5sum "$f" | cut -d' ' -f1)" \
        "$(stat -c%s "$f")" \
        "${f#dists/stable/}"
    done
    
    echo "SHA256:"
    for f in dists/stable/main/binary-*/Packages{,.gz}; do
      [[ -f "$f" ]] || continue
      printf " %s %16d %s\n" \
        "$(sha256sum "$f" | cut -d' ' -f1)" \
        "$(stat -c%s "$f")" \
        "${f#dists/stable/}"
    done
  } >> "dists/stable/Release"
  
  # Sign the Release file
  local gpg_key_id
  gpg_key_id=$(get_gpg_key_id)
  
  if [[ -n "$gpg_key_id" ]]; then
    log "Signing Release with GPG key: $gpg_key_id"
    
    # Create detached signature (for apt-get with signed-by)
    gpg --detach-sign --armor -u "$gpg_key_id" \
        -o "dists/stable/Release.gpg" "dists/stable/Release"
    
    # Create inline signed release (for older apt)
    gpg --clearsign -u "$gpg_key_id" \
        -o "dists/stable/InRelease" "dists/stable/Release"
    
    log "✓ Release file signed"
  else
    warn "No GPG key found. Repository will be unsigned."
    # Still create Release.gpg as empty for compatibility
    touch "dists/stable/Release.gpg"
  fi
}

# ── Export GPG key ────────────────────────────────────────────────────────────

export_gpg_key() {
  local gpg_key_id
  gpg_key_id=$(get_gpg_key_id)
  
  if [[ -n "$gpg_key_id" ]]; then
    local key_file="$REPO_DIR/HELIUM-GPG-KEY"
    gpg --armor --export "$gpg_key_id" > "$key_file"
    log "GPG key exported to: $key_file"
  fi
}

# ── Create distribution aliases ───────────────────────────────────────────────

create_dist_aliases() {
  local apt_dists=()
  
  if [[ -n "${APT_DISTS:-}" ]]; then
    IFS=' ' read -r -a apt_dists <<<"$APT_DISTS"
  else
    apt_dists=("${APT_DISTS_DEFAULT[@]}")
  fi
  
  log "Creating distribution aliases: ${apt_dists[*]}"
  
  for dist in "${apt_dists[@]}"; do
    [[ "$dist" == "stable" ]] && continue
    
    rm -rf "dists/$dist"
    cp -a "dists/stable" "dists/$dist"
    
    # Update Release file for this distro
    sed -i \
      -e "s/^Suite: .*/Suite: $dist/" \
      -e "s/^Codename: .*/Codename: $dist/" \
      "dists/$dist/Release"
    
    # Re-sign if we have a key
    local gpg_key_id
    gpg_key_id=$(get_gpg_key_id)
    if [[ -n "$gpg_key_id" ]]; then
      gpg --detach-sign --armor -u "$gpg_key_id" \
          -o "dists/$dist/Release.gpg" "dists/$dist/Release"
      gpg --clearsign -u "$gpg_key_id" \
          -o "dists/$dist/InRelease" "dists/$dist/Release"
    fi
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  log "Generating signed APT repository..."
  
  setup_repo_dirs
  copy_packages
  generate_packages
  generate_signed_release
  export_gpg_key
  create_dist_aliases
  
  log "✓ APT repository ready: $REPO_DIR"
  log "  Add to sources.list:"
  log "    deb [signed-by=/usr/share/keyrings/helium.gpg] ${HELIUM_REPO_URL}/apt stable main"
}

main "$@"
