#!/usr/bin/env bash
# ==============================================================================
# publish.sh — Build APT + RPM repos from dist/ and atomically deploy
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="PUBLISH"

# ── Configuration ─────────────────────────────────────────────────────────────

readonly DIST_DIR="${DIST_DIR:-dist}"
readonly REPO_DIR="${REPO_DIR:-$HELIUM_PROJECT_ROOT/site/public}"
readonly STAGING_DIR="${STAGING_DIR:-$HELIUM_PROJECT_ROOT/site/public.tmp}"
readonly CURRENT_DIR="${CURRENT_DIR:-$HELIUM_PROJECT_ROOT/site/public.current}"
readonly BACKUP_DIR="${BACKUP_DIR:-$HELIUM_PROJECT_ROOT/.backups}"
readonly LOCK_FILE="/tmp/helium-publish.lock"

readonly APT_REPO_DIR="$STAGING_DIR/apt"
readonly RPM_REPO_DIR="$STAGING_DIR/rpm"

readonly APT_DIST_ALIASES=(noble jammy focal bookworm bullseye)

# ── Helpers ───────────────────────────────────────────────────────────────────

die_with_restore() {
  warn "Publish failed — restoring previous state"
  if [[ -d "$CURRENT_DIR" ]]; then
    rm -rf "$REPO_DIR"
    mv "$CURRENT_DIR" "$REPO_DIR"
  fi
  exit 1
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    err "Another publish operation is in progress ($LOCK_FILE)"
  fi
  touch "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

# ── Package validation ────────────────────────────────────────────────────────

validate_packages() {
  log "Validating packages in $DIST_DIR..."

  [[ -d "$DIST_DIR" ]] || err "Distribution directory not found: $DIST_DIR"

  local deb_count=0 rpm_count=0
  local has_deb_amd64=false has_deb_arm64=false
  local has_rpm_x86=false  has_rpm_arm=false

  for deb in "$DIST_DIR"/*.deb; do
    [[ -f "$deb" ]] || continue
    dpkg -I "$deb" >/dev/null 2>&1 || err "Invalid DEB: $deb"
    (( ++deb_count ))
    local name="${deb,,}"
    [[ "$name" == *amd64* || "$name" == *x86_64* ]] && has_deb_amd64=true
    [[ "$name" == *arm64* || "$name" == *aarch64* ]] && has_deb_arm64=true
  done

  for rpm_file in "$DIST_DIR"/*.rpm; do
    [[ -f "$rpm_file" ]] || continue
    (( ++rpm_count ))
    local name="${rpm_file,,}"
    [[ "$name" == *x86_64* || "$name" == *amd64* ]]  && has_rpm_x86=true
    [[ "$name" == *aarch64* || "$name" == *arm64* ]]  && has_rpm_arm=true
  done

  (( deb_count + rpm_count > 0 )) || err "No packages found in $DIST_DIR"

  [[ "$has_deb_amd64" == "true" ]] || err "Missing amd64 .deb"
  [[ "$has_deb_arm64" == "true" ]] || err "Missing arm64 .deb"
  [[ "$has_rpm_x86"   == "true" ]] || err "Missing x86_64 .rpm"
  [[ "$has_rpm_arm"   == "true" ]] || err "Missing aarch64 .rpm"

  log "Found $deb_count DEB and $rpm_count RPM packages"
}

# ── Backups ───────────────────────────────────────────────────────────────────

backup_repos() {
  log "Backing up current repositories..."
  mkdir -p "$BACKUP_DIR"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"

  for component in apt rpm; do
    if [[ -d "$REPO_DIR/$component" ]]; then
      tar -czf "$BACKUP_DIR/repo_${ts}_${component}.tar.gz" -C "$REPO_DIR" "$component" 2>/dev/null || true
      log "Backup: $BACKUP_DIR/repo_${ts}_${component}.tar.gz"
    fi
  done
}

# ── Determine architecture of a .deb by filename or metadata ──────────────────

deb_arch_dir() {
  local deb="$1"
  local base
  base="$(basename "$deb")"

  if [[ "$base" =~ [/_](amd64|x86_64)\.deb$ ]]; then
    echo "pool/main-amd64"; return
  elif [[ "$base" =~ [/_](arm64|aarch64)\.deb$ ]]; then
    echo "pool/main-arm64"; return
  fi

  # Fallback: read from package metadata
  local pkg_arch
  pkg_arch="$(dpkg -I "$deb" 2>/dev/null | grep -i '^ Architecture:' | cut -d: -f2 | xargs || true)"
  case "$pkg_arch" in
    amd64|x86_64)  echo "pool/main-amd64" ;;
    arm64|aarch64) echo "pool/main-arm64" ;;
    *)             warn "Unknown arch for $base: $pkg_arch"; echo "" ;;
  esac
}

# ── APT repository ────────────────────────────────────────────────────────────

publish_apt() {
  log "Publishing APT repository..."

  mkdir -p "$APT_REPO_DIR/pool/main" \
           "$APT_REPO_DIR/pool/main-amd64" \
           "$APT_REPO_DIR/pool/main-arm64" \
           "$APT_REPO_DIR/dists/stable/main/binary-amd64" \
           "$APT_REPO_DIR/dists/stable/main/binary-arm64"

  # Copy packages into architecture-specific pools
  for deb in "$DIST_DIR"/*.deb; do
    [[ -f "$deb" ]] || continue
    local arch_dir
    arch_dir="$(deb_arch_dir "$deb")"
    [[ -z "$arch_dir" ]] && continue

    local base
    base="$(basename "$deb")"

    if [[ -f "$APT_REPO_DIR/$arch_dir/$base" ]]; then
      local new_hash old_hash
      new_hash="$(sha256sum "$deb" | cut -d' ' -f1)"
      old_hash="$(sha256sum "$APT_REPO_DIR/$arch_dir/$base" | cut -d' ' -f1)"
      if [[ "$new_hash" == "$old_hash" ]]; then
        log "Unchanged: $base"; continue
      fi
      log "Replacing: $base"
    else
      log "Adding: $base"
    fi

    cp "$deb" "$APT_REPO_DIR/$arch_dir/"
    cp "$deb" "$APT_REPO_DIR/pool/main/"
  done

  # Generate Packages + Release
  cd "$APT_REPO_DIR"

  for arch in amd64 arm64; do
    log "Generating $arch Packages..."
    dpkg-scanpackages "pool/main-$arch" 2>/dev/null \
      | awk -v RS='' -v ORS='\n\n' '$0 ~ /^Package:/' \
      > "dists/stable/main/binary-$arch/Packages" \
      || err "dpkg-scanpackages failed for $arch"

    [[ -s "dists/stable/main/binary-$arch/Packages" ]] \
      || err "No $arch packages found in pool/main-$arch"
    validate_packages_file "dists/stable/main/binary-$arch/Packages"
    gzip -k -f "dists/stable/main/binary-$arch/Packages" \
      || err "Failed to gzip $arch Packages"
  done

  # Release file
  local release_date
  release_date="$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S %Z')"

  cat > dists/stable/Release <<RELEASE
Origin: ${HELIUM_PACKAGE_NAME}
Label: ${HELIUM_PACKAGE_NAME}
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Helium Browser Repository
Date: ${release_date}
RELEASE

  # Checksums
  {
    echo "MD5Sum:"
    for f in dists/stable/main/binary-*/Packages*; do
      [[ -f "$f" ]] || continue
      printf " %s %8s %s\n" \
        "$(md5sum "$f" | cut -d' ' -f1)" \
        "$(file_size "$f")" \
        "${f#dists/stable/}"
    done
    echo "SHA256:"
    for f in dists/stable/main/binary-*/Packages*; do
      [[ -f "$f" ]] || continue
      printf " %s %8s %s\n" \
        "$(sha256sum "$f" | cut -d' ' -f1)" \
        "$(file_size "$f")" \
        "${f#dists/stable/}"
    done
  } >> dists/stable/Release

  # Distribution aliases
  for dist in "${APT_DIST_ALIASES[@]}"; do
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
  log "APT repository updated."
}

# ── RPM repository ────────────────────────────────────────────────────────────

publish_rpm() {
  log "Publishing RPM repository..."

  mkdir -p "$RPM_REPO_DIR/x86_64" "$RPM_REPO_DIR/aarch64"

  for rpm_file in "$DIST_DIR"/*.rpm; do
    [[ -f "$rpm_file" ]] || continue
    local base arch="x86_64"
    base="$(basename "$rpm_file")"

    if [[ "$rpm_file" == *aarch64* || "$rpm_file" == *arm64* ]]; then
      arch="aarch64"
    fi

    if [[ -f "$RPM_REPO_DIR/$arch/$base" ]]; then
      local new_hash old_hash
      new_hash="$(sha256sum "$rpm_file" | cut -d' ' -f1)"
      old_hash="$(sha256sum "$RPM_REPO_DIR/$arch/$base" | cut -d' ' -f1)"
      [[ "$new_hash" == "$old_hash" ]] && { log "Unchanged: $base"; continue; }
      log "Replacing: $base"
    else
      log "Adding: $base ($arch)"
    fi

    cp "$rpm_file" "$RPM_REPO_DIR/$arch/"
  done

  cd "$RPM_REPO_DIR"
  for arch in x86_64 aarch64; do
    if compgen -G "$arch/*.rpm" >/dev/null; then
      log "Generating metadata for $arch..."
      if command -v createrepo_c >/dev/null 2>&1; then
        createrepo_c --update "$arch" 2>/dev/null || createrepo_c "$arch" 2>/dev/null \
          || err "createrepo_c failed for $arch"
      elif command -v createrepo >/dev/null 2>&1; then
        createrepo --update "$arch" 2>/dev/null || createrepo "$arch" 2>/dev/null \
          || err "createrepo failed for $arch"
      else
        err "Neither createrepo_c nor createrepo found."
      fi
      validate_rpm_metadata "$RPM_REPO_DIR/$arch"
    else
      err "No RPM packages for $arch"
    fi
  done
  cd - >/dev/null
  log "RPM repository updated."
}

# ── Manifest ──────────────────────────────────────────────────────────────────

generate_manifest() {
  local manifest="$STAGING_DIR/MANIFEST.txt"
  local ts
  ts="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"

  cat > "$manifest" <<MANIFEST
Helium Browser Repository Manifest
Generated: $ts

=== APT Repository ===
Location: $APT_REPO_DIR
Distributions: stable ${APT_DIST_ALIASES[*]}
Architectures: amd64 arm64

Packages:
MANIFEST

  shopt -s nullglob
  for deb in "$APT_REPO_DIR/pool/main"/*.deb; do
    printf '  %s  (size: %s, sha256: %s)\n' \
      "$(basename "$deb")" "$(file_size "$deb")" "$(sha256sum "$deb" | cut -d' ' -f1)" \
      >> "$manifest"
  done

  cat >> "$manifest" <<MANIFEST

=== RPM Repository ===
Location: $RPM_REPO_DIR
Architectures: x86_64 aarch64

Packages:
MANIFEST

  for rpm_file in "$RPM_REPO_DIR"/*/*.rpm; do
    printf '  %s  (size: %s, sha256: %s)\n' \
      "$(basename "$rpm_file")" "$(file_size "$rpm_file")" "$(sha256sum "$rpm_file" | cut -d' ' -f1)" \
      >> "$manifest"
  done
  shopt -u nullglob

  log "Manifest: $manifest"
}

# ── Main ──────────────────────────────────────────────────────────────────────

check_deps_warn dpkg-scanpackages gzip createrepo_c sha256sum
acquire_lock
trap 'die_with_restore' ERR

log "Starting publication..."
log "  dist:    $DIST_DIR"
log "  repo:    $REPO_DIR"
log "  staging: $STAGING_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp "$HELIUM_PROJECT_ROOT/site/install.sh"     "$STAGING_DIR/install.sh"
cp "$HELIUM_PROJECT_ROOT/site/install-rpm.sh"  "$STAGING_DIR/install-rpm.sh"

validate_packages
backup_repos
publish_apt
publish_rpm

# Copy install scripts into repo subdirectories too
cp "$STAGING_DIR/install.sh"     "$APT_REPO_DIR/install.sh"
cp "$STAGING_DIR/install-rpm.sh" "$RPM_REPO_DIR/install-rpm.sh"

cp "$HELIUM_PROJECT_ROOT/site/index.html.template" "$STAGING_DIR/index.html"

generate_manifest

"$HELIUM_PROJECT_ROOT/scripts/utils/validate.sh" "$APT_REPO_DIR" "$RPM_REPO_DIR" "$STAGING_DIR"

# Atomic swap
rm -rf "$CURRENT_DIR"
if [[ -d "$REPO_DIR" ]]; then
  mv "$REPO_DIR" "$CURRENT_DIR"
fi
mv "$STAGING_DIR" "$REPO_DIR"
rm -rf "$CURRENT_DIR"

log "Publication completed successfully."

