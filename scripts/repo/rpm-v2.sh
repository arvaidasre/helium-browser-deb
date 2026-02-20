#!/usr/bin/env bash
# ==============================================================================
# rpm-v2.sh — Generate signed RPM repository
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="RPM-v2"

readonly REPO_DIR="${1:-site/public/rpm}"
readonly CHANNEL="${CHANNEL:-stable}"

# ── Dependencies ──────────────────────────────────────────────────────────────

if command -v createrepo_c >/dev/null 2>&1; then
  CREATEREPO="createrepo_c"
elif command -v createrepo >/dev/null 2>&1; then
  CREATEREPO="createrepo"
else
  err "Missing: createrepo or createrepo_c (dnf install createrepo_c)"
fi

check_deps gpg "$CREATEREPO"

# ── GPG Setup ─────────────────────────────────────────────────────────────────

get_gpg_key_id() {
  gpg --list-secret-keys --keyid-format LONG 2>/dev/null | \
    grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2 || true
}

# ── Setup directories ─────────────────────────────────────────────────────────

setup_repo_dirs() {
  log "Setting up RPM repository in $REPO_DIR..."
  mkdir -p "$REPO_DIR/x86_64" "$REPO_DIR/aarch64"
}

# ── Copy packages ─────────────────────────────────────────────────────────────

copy_packages() {
  [[ -d "dist" ]] || { warn "dist/ not found — repo will be empty."; return; }
  
  log "Copying RPM packages..."
  for rpm_file in dist/*.rpm; do
    [[ -f "$rpm_file" ]] || continue
    
    if [[ "$rpm_file" == *x86_64* ]]; then
      cp "$rpm_file" "$REPO_DIR/x86_64/"
    elif [[ "$rpm_file" == *aarch64* || "$rpm_file" == *arm64* ]]; then
      cp "$rpm_file" "$REPO_DIR/aarch64/"
    else
      warn "Unknown arch: $(basename "$rpm_file"), using x86_64"
      cp "$rpm_file" "$REPO_DIR/x86_64/"
    fi
  done
}

# ── Generate repository metadata ─────────────────────────────────────────────-

generate_metadata() {
  cd "$REPO_DIR"
  
  for arch in x86_64 aarch64; do
    if compgen -G "$arch/*.rpm" >/dev/null; then
      log "Generating metadata for $arch..."
      
      # Use createrepo with checksum options
      if [[ "$CREATEREPO" == "createrepo_c" ]]; then
        "$CREATEREPO" --update \
          --checksum sha256 \
          --unique-md-filenames \
          --retain-old-md-by 3 \
          "$arch"
      else
        "$CREATEREPO" --update \
          --checksum sha \
          --unique-md-filenames \
          "$arch"
      fi
    else
      warn "No packages for $arch"
    fi
  done
}

# ── Sign repository metadata ──────────────────────────────────────────────────

sign_metadata() {
  local gpg_key_id
  gpg_key_id=$(get_gpg_key_id)
  
  if [[ -z "$gpg_key_id" ]]; then
    warn "No GPG key found. Repository metadata will be unsigned."
    return
  fi
  
  log "Signing repository metadata with key: $gpg_key_id"
  
  # Export public key
  gpg --armor --export "$gpg_key_id" > "RPM-GPG-KEY-helium"
  
  for arch in x86_64 aarch64; do
    if [[ -d "$arch/repodata" ]]; then
      log "Signing $arch repodata..."
      
      # Sign repomd.xml
      if [[ -f "$arch/repodata/repomd.xml" ]]; then
        gpg --detach-sign --armor -u "$gpg_key_id" \
            -o "$arch/repodata/repomd.xml.asc" \
            "$arch/repodata/repomd.xml"
      fi
    fi
  done
  
  # Create repo config file
  cat > "helium.repo" <<REPO
[helium]
name=Helium Browser Repository
baseurl=${HELIUM_REPO_URL}/rpm/\$basearch
enabled=1
gpgcheck=1
gpgkey=${HELIUM_REPO_URL}/rpm/RPM-GPG-KEY-helium
repo_gpgcheck=1
REPO

  log "✓ Repository metadata signed"
}

# ── Export GPG key with instructions ──────────────────────────────────────────

export_gpg_key() {
  local gpg_key_id
  gpg_key_id=$(get_gpg_key_id)
  
  if [[ -n "$gpg_key_id" ]]; then
    gpg --armor --export "$gpg_key_id" > "$REPO_DIR/RPM-GPG-KEY-helium"
    log "GPG key exported to: $REPO_DIR/RPM-GPG-KEY-helium"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  log "Generating signed RPM repository..."
  
  setup_repo_dirs
  copy_packages
  generate_metadata
  sign_metadata
  export_gpg_key
  
  log "✓ RPM repository ready: $REPO_DIR"
  log "  Install with:"
  log "    sudo rpm --import ${HELIUM_REPO_URL}/rpm/RPM-GPG-KEY-helium"
  log "    sudo dnf config-manager --add-repo ${HELIUM_REPO_URL}/rpm/helium.repo"
}

main "$@"
