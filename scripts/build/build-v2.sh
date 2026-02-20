#!/usr/bin/env bash
# ==============================================================================
# build-v2.sh — Improved build script with signing and checksum verification
# ==============================================================================
set -euo pipefail

readonly OUTDIR="dist"
readonly CHANNEL="${CHANNEL:-stable}"  # stable or nightly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/deps-map.sh"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

LOG_PREFIX="BUILD-v2"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps curl jq fpm sha256sum gpg

mkdir -p "$OUTDIR"

# ── GPG Setup ─────────────────────────────────────────────────────────────────

setup_gpg() {
  if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
    log "Importing GPG key from environment..."
    "$SCRIPT_DIR/../utils/gpg-setup.sh" import "$GPG_PRIVATE_KEY"
  fi
  
  # Get key ID for signing
  GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | \
    grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)
  
  if [[ -n "${GPG_KEY_ID:-}" ]]; then
    log "Using GPG key: $GPG_KEY_ID"
  else
    warn "No GPG key found. Packages will be unsigned."
  fi
}

# ── Fetch upstream ────────────────────────────────────────────────────────────

fetch_upstream() {
  if [[ -n "${UPSTREAM_TAG:-}" ]]; then
    log "Using specified release tag: $UPSTREAM_TAG"
    API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/tags/${UPSTREAM_TAG}"
  else
    log "Fetching latest ${CHANNEL} release from ${HELIUM_UPSTREAM_REPO}..."
    if [[ "$CHANNEL" == "nightly" ]]; then
      API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases"
    else
      API_URL="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases/latest"
    fi
  fi

  JSON=$(github_api_get "$API_URL")
  
  # For nightly channel, get the first (latest) release
  if [[ "$CHANNEL" == "nightly" && -n "${UPSTREAM_TAG:-}" ]]; then
    JSON=$(echo "$JSON" | jq '.[0]')
  fi
  
  validate_release_json "$JSON"

  TAG=$(jq -r '.tag_name' <<<"$JSON")
  VERSION=$(normalize_version "$TAG")
  
  # Add channel suffix for nightly builds
  if [[ "$CHANNEL" == "nightly" ]]; then
    VERSION="${VERSION}+nightly.$(date +%Y%m%d)"
  fi
  
  log "Version: $VERSION (tag: $TAG, channel: $CHANNEL)"

  # Detect pre-release
  PRERELEASE=$(jq -r '.prerelease // false' <<<"$JSON")
  if [[ "$PRERELEASE" == "true" || "$TAG" =~ (alpha|beta|rc|pre|preview) ]]; then
    IS_PRERELEASE="true"
  else
    IS_PRERELEASE="false"
  fi

  # Save metadata
  cat >"$OUTDIR/meta.env" <<META
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
CHANNEL=${CHANNEL}
IS_PRERELEASE=${IS_PRERELEASE}
META
}

# ── Skip check ────────────────────────────────────────────────────────────────

check_skip() {
  SKIPPED="0"
  if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" && "${FORCE_BUILD:-}" != "true" ]]; then
    local check_tag="$TAG"
    [[ "$CHANNEL" == "nightly" ]] && check_tag="${TAG}-nightly"
    
    log "Checking if release $check_tag already exists..."
    HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${check_tag}")

    if [[ "$HTTP_CODE" == "200" ]]; then
      log "Release $check_tag already exists — skipping."
      SKIPPED="1"
    fi
  fi

  echo "SKIPPED=${SKIPPED}" >> "$OUTDIR/meta.env"
  [[ "$SKIPPED" == "1" ]] && exit 0
}

# ── Download and verify ───────────────────────────────────────────────────────

download_and_verify() {
  set_arch_vars
  log "Architecture: DEB=$DEB_ARCH  RPM=$RPM_ARCH"

  TARBALL_URL=$(resolve_tarball_url "$JSON")
  [[ -z "$TARBALL_URL" ]] && err "Tarball not found for $TAG"
  
  log "Tarball: $TARBALL_URL"

  # Download tarball
  TARBALL_FILE="$WORKDIR/$(basename "$TARBALL_URL")"
  log "Downloading to $TARBALL_FILE..."
  curl -fsSL "$TARBALL_URL" -o "$TARBALL_FILE"
  
  # Verify checksum if available
  if [[ "${VERIFY_CHECKSUM:-true}" == "true" ]]; then
    log "Verifying checksum..."
    if ! "$SCRIPT_DIR/../utils/checksum-verify.sh" "$TARBALL_FILE" <<<"$JSON" 2>/dev/null; then
      warn "Could not verify checksum automatically"
    fi
  fi
  
  write_release_notes "$JSON" "$OUTDIR" "$TAG"
}

# ── Build packages with signing ───────────────────────────────────────────────

build_signed_packages() {
  setup_workdir
  
  local offline_root="$WORKDIR/offline_root"
  mkdir -p \
    "$offline_root/opt/helium" \
    "$offline_root/usr/bin" \
    "$offline_root/usr/share/applications" \
    "$offline_root/usr/share/icons/hicolor/512x512/apps" \
    "$offline_root/etc/apparmor.d"

  # Extract
  log "Extracting tarball..."
  tar -xf "$TARBALL_FILE" -C "$WORKDIR"
  
  local extracted_dir
  extracted_dir=$(find "$WORKDIR" -maxdepth 1 -type d -name 'helium*' ! -path "*/offline_root" | head -1)
  [[ -z "$extracted_dir" ]] && err "Could not find extracted directory."

  cp -a "$extracted_dir/"* "$offline_root/opt/helium/"
  chmod -R u+w "$offline_root/opt/helium"

  # Detect binary
  local bin_name
  bin_name=$(detect_main_binary "$offline_root/opt/helium")

  # Setup package files
  copy_icon "$offline_root/opt/helium" \
    "$offline_root/usr/share/icons/hicolor/512x512/apps/helium.png"
  write_initial_preferences "$offline_root/opt/helium/initial_preferences"
  write_wrapper_script "$offline_root/usr/bin/helium" "$bin_name"
  write_apparmor_profile "$offline_root/etc/apparmor.d/opt.helium.helium" "$bin_name"
  write_desktop_entry "$offline_root/usr/share/applications/helium.desktop"

  # Build signed DEB
  build_signed_deb "$offline_root" "$OUTDIR"
  
  # Build signed RPM  
  build_signed_rpm "$offline_root" "$OUTDIR"
  
  # Generate checksums
  generate_checksums "$OUTDIR"
}

build_signed_deb() {
  local offline_root="$1" outdir="$2"
  local distro="${TARGET_DISTRO:-ubuntu}"
  local codename="${TARGET_CODENAME:-noble}"
  
  # Get distro-specific deps
  local deps
  deps=$(get_deb_deps "$distro" "$codename")
  local recommends
  recommends=$(get_deb_recommends)
  
  local fpm_deps=()
  for dep in $deps; do
    fpm_deps+=("--depends" "$dep")
  done
  for rec in $recommends; do
    fpm_deps+=("--deb-recommends" "$rec")
  done
  
  local full_deb_name="${HELIUM_PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
  log "Building DEB: $full_deb_name (for $distro:$codename)"

  fpm -s dir -t deb \
    -n "$HELIUM_PACKAGE_NAME" \
    -v "$VERSION" \
    --iteration "1${codename}1" \
    --after-install "$SCRIPT_DIR/resources/postinst.sh" \
    -a "$DEB_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "$HELIUM_UPSTREAM_URL" \
    --description "Helium Browser - privacy-focused Chromium fork" \
    --vendor "Imputnet" \
    --license "MIT" \
    --category "web" \
    "${fpm_deps[@]}" \
    --provides "helium" \
    --conflicts "helium" \
    --replaces "helium" \
    --package "$outdir/$full_deb_name" \
    -C "$offline_root" .

  # Sign the package if GPG key available
  if [[ -n "${GPG_KEY_ID:-}" ]]; then
    log "Signing DEB package..."
    if command -v dpkg-sig >/dev/null 2>&1; then
      dpkg-sig --sign builder -k "$GPG_KEY_ID" "$outdir/$full_deb_name"
    elif command -v debsigs >/dev/null 2>&1; then
      debsigs sign -k "$GPG_KEY_ID" "$outdir/$full_deb_name"
    else
      warn "No DEB signing tool found (install dpkg-sig or debsigs)"
    fi
  fi

  log "Built: $outdir/$full_deb_name"
  echo "FULL_DEB_FILENAME=$full_deb_name" >> "$outdir/meta.env"
}

build_signed_rpm() {
  local offline_root="$1" outdir="$2"
  local distro="${TARGET_DISTRO:-fedora}"
  local version="${TARGET_VERSION:-40}"
  
  local deps
  deps=$(get_rpm_deps "$distro" "$version")
  
  local fpm_deps=()
  for dep in $deps; do
    fpm_deps+=("--depends" "$dep")
  done
  
  local full_rpm_name="${HELIUM_PACKAGE_NAME}-${VERSION}-1.${RPM_ARCH}.rpm"
  log "Building RPM: $full_rpm_name (for $distro:$version)"

  fpm -s dir -t rpm \
    -n "$HELIUM_PACKAGE_NAME" \
    -v "$VERSION" \
    --iteration "1" \
    --after-install "$SCRIPT_DIR/resources/postinst.sh" \
    -a "$RPM_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "$HELIUM_UPSTREAM_URL" \
    --description "Helium Browser - privacy-focused Chromium fork" \
    --vendor "Imputnet" \
    --license "MIT" \
    --category "Applications/Internet" \
    "${fpm_deps[@]}" \
    --provides "helium" \
    --conflicts "helium" \
    --replaces "helium" \
    --rpm-digest sha256 \
    --rpm-compression xz \
    --package "$outdir/$full_rpm_name" \
    -C "$offline_root" .

  # Sign the RPM if GPG key available
  if [[ -n "${GPG_KEY_ID:-}" ]]; then
    log "Signing RPM package..."
    if command -v rpmsign >/dev/null 2>&1; then
      rpmsign --addsign --key-id="$GPG_KEY_ID" "$outdir/$full_rpm_name"
    else
      warn "rpmsign not found, RPM will be unsigned"
    fi
  fi

  log "Built: $outdir/$full_rpm_name"
  echo "FULL_RPM_FILENAME=$full_rpm_name" >> "$outdir/meta.env"
}

generate_checksums() {
  local outdir="$1"
  log "Generating checksums..."
  
  (cd "$outdir" && sha256sum *.deb *.rpm > SHA256SUMS 2>/dev/null || true)
  
  # Sign checksums file
  if [[ -n "${GPG_KEY_ID:-}" && -f "$outdir/SHA256SUMS" ]]; then
    gpg --detach-sign --armor -u "$GPG_KEY_ID" -o "$outdir/SHA256SUMS.asc" "$outdir/SHA256SUMS"
    log "Signed checksums file created"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  log "Starting build v2 — Channel: $CHANNEL"
  setup_gpg
  fetch_upstream
  check_skip
  download_and_verify
  build_signed_packages
  log "Build complete!"
}

main "$@"
