#!/usr/bin/env bash
# ==============================================================================
# Build helpers — functions specific to package building
# ==============================================================================
# Sourced by build.sh and prerelease.sh. Generic helpers live in lib/common.sh.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="BUILD"

# ─── Release notes ────────────────────────────────────────────────────────────

write_release_notes() {
  local json="$1" outdir="$2" tag_name="$3"
  local title body

  title="$(jq -r '.name // ""' <<<"$json")"
  [[ -z "$title" ]] && title="$tag_name"
  body="$(jq -r '.body // ""' <<<"$json")"

  echo "$title" > "$outdir/release_title.txt"
  echo "$body"  > "$outdir/release_notes.md"
}

# ─── Temp work directory ─────────────────────────────────────────────────────

setup_workdir() {
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
}

# ─── Packaging fragments ─────────────────────────────────────────────────────

write_initial_preferences() {
  cat >"$1" <<'PREFS'
{
  "homepage_is_newtabpage": true,
  "browser": {
    "show_home_button": true
  }
}
PREFS
  chmod 644 "$1"
}

write_wrapper_script() {
  local target="$1" bin_name="$2"
  cat >"$target" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/helium\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

# Custom flags (add your chrome://flags overrides here)
EXTRA_FLAGS=""

exec /opt/helium/$bin_name \$EXTRA_FLAGS "\$@"
WRAPPER
  chmod +x "$target"
}

write_apparmor_profile() {
  local target="$1" bin_name="$2"
  cat >"$target" <<APPARMOR
abi <abi/4.0>,
include <tunables/global>

/opt/helium/$bin_name flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/opt.helium.helium>
}
APPARMOR
}

write_desktop_entry() {
  cat >"$1" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Helium
Comment=Helium Browser
Exec=/usr/bin/helium %U
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=helium
DESKTOP
}

# ─── Detect main binary ──────────────────────────────────────────────────────

detect_main_binary() {
  local root="$1"
  local bin_name=""

  for b in helium chrome google-chrome chromium; do
    if [[ -f "$root/$b" ]]; then
      bin_name="$b"
      log "Detected binary: $bin_name"
      break
    fi
  done

  if [[ -z "$bin_name" ]]; then
    bin_name="$(find "$root" -maxdepth 1 -executable -type f -printf '%f\n' | head -n 1)"
    if [[ -z "$bin_name" ]]; then
      bin_name="helium"
      warn "Could not detect binary name, defaulting to helium."
    else
      log "Detected binary (fallback): $bin_name"
    fi
  fi

  echo "$bin_name"
}

# ─── Copy icon ────────────────────────────────────────────────────────────────

copy_icon() {
  local src_dir="$1" dest="$2"

  if [[ -f "$src_dir/helium.png" ]]; then
    cp "$src_dir/helium.png" "$dest"
  elif [[ -f "$src_dir/product_logo_256.png" ]]; then
    cp "$src_dir/product_logo_256.png" "$dest"
  fi
}

# ─── Build DEB and RPM from an extracted tarball ──────────────────────────────

build_offline_packages() {
  local tarball_url="$1" outdir="$2"

  log "Preparing offline root..."
  local offline_root="$WORKDIR/offline_root"
  mkdir -p \
    "$offline_root/opt/helium" \
    "$offline_root/usr/bin" \
    "$offline_root/usr/share/applications" \
    "$offline_root/usr/share/icons/hicolor/512x512/apps" \
    "$offline_root/etc/apparmor.d"

  # Download and extract tarball
  log "Downloading tarball..."
  local tarball_file="${tarball_url##*/}"
  local tarball_path
  if [[ "$tarball_file" == *.tar.* ]]; then
    tarball_path="$WORKDIR/$tarball_file"
  else
    tarball_path="$WORKDIR/helium.tar.${tarball_file##*.}"
  fi

  curl -fsSL "$tarball_url" -o "$tarball_path"
  tar -xf "$tarball_path" -C "$WORKDIR"

  local extracted_dir
  extracted_dir="$(find "$WORKDIR" -maxdepth 1 -type d -name 'helium*' | head -n 1)"
  [[ -z "$extracted_dir" ]] && err "Could not find extracted directory."

  cp -a "$extracted_dir/"* "$offline_root/opt/helium/"
  chmod -R u+w "$offline_root/opt/helium"

  # Detect binary & populate package tree
  local bin_name
  bin_name="$(detect_main_binary "$offline_root/opt/helium")"

  copy_icon "$offline_root/opt/helium" \
    "$offline_root/usr/share/icons/hicolor/512x512/apps/helium.png"

  write_initial_preferences "$offline_root/opt/helium/initial_preferences"
  write_wrapper_script      "$offline_root/usr/bin/helium" "$bin_name"
  write_apparmor_profile    "$offline_root/etc/apparmor.d/opt.helium.helium" "$bin_name"
  write_desktop_entry       "$offline_root/usr/share/applications/helium.desktop"

  # Build packages
  package_deb "$offline_root" "$outdir"
  package_rpm "$offline_root" "$outdir"

  # Checksums
  if [[ -f "$outdir/meta.env" ]]; then
    # shellcheck disable=SC1090
    source "$outdir/meta.env"
    if [[ -n "${FULL_DEB_FILENAME:-}" && -n "${FULL_RPM_FILENAME:-}" ]]; then
      local sum_file="SHA256SUMS-${ARCH:-unknown}"
      log "Generating checksums: $sum_file"
      (cd "$outdir" && sha256sum "$FULL_DEB_FILENAME" "$FULL_RPM_FILENAME" > "$sum_file")
    fi
  fi

  log "Done."
}

# ─── FPM wrappers ─────────────────────────────────────────────────────────────

package_deb() {
  local offline_root="$1" outdir="$2"
  local full_deb_name="${HELIUM_PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"

  log "Building DEB: $full_deb_name"

  fpm -s dir -t deb \
    -n "$HELIUM_PACKAGE_NAME" \
    -v "$VERSION" \
    --after-install "$SCRIPT_DIR/resources/postinst.sh" \
    -a "$DEB_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "$HELIUM_UPSTREAM_URL" \
    --description "Helium Browser (Offline)" \
    --vendor "Imputnet" \
    --license "MIT" \
    --depends "ca-certificates" \
    --depends "libgtk-3-0" \
    --depends "libnss3" \
    --depends "libxss1" \
    --depends "libasound2" \
    --depends "libgbm1" \
    --deb-recommends "apparmor" \
    --provides "helium" \
    --conflicts "helium" \
    --replaces "helium" \
    --package "$outdir/$full_deb_name" \
    -C "$offline_root" .

  log "Built: $outdir/$full_deb_name"
  echo "FULL_DEB_FILENAME=$full_deb_name" >> "$outdir/meta.env"
}

package_rpm() {
  local offline_root="$1" outdir="$2"
  local full_rpm_name="${HELIUM_PACKAGE_NAME}-${VERSION}-${RPM_ARCH}.rpm"

  log "Building RPM: $full_rpm_name"

  fpm -s dir -t rpm \
    -n "$HELIUM_PACKAGE_NAME" \
    -v "$VERSION" \
    --after-install "$SCRIPT_DIR/resources/postinst.sh" \
    -a "$RPM_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "$HELIUM_UPSTREAM_URL" \
    --description "Helium Browser (Offline)" \
    --vendor "Imputnet" \
    --license "MIT" \
    --depends "ca-certificates" \
    --depends "gtk3" \
    --depends "nss" \
    --depends "libXScrnSaver" \
    --depends "alsa-lib" \
    --depends "mesa-libgbm" \
    --depends "libdrm" \
    --depends "xdg-utils" \
    --provides "helium" \
    --conflicts "helium" \
    --replaces "helium" \
    --package "$outdir/$full_rpm_name" \
    -C "$offline_root" .

  log "Built: $outdir/$full_rpm_name"
  echo "FULL_RPM_FILENAME=$full_rpm_name" >> "$outdir/meta.env"
}
