#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\033[1;34m[BUILD]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

check_deps() {
  local deps=(curl jq fpm sha256sum)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Missing dependency: $cmd"
    fi
  done
}

normalize_version() {
  local v="$1"
  v="${v#v}"
  v="${v// /}"
  v="${v//_/.}"
  echo "$v"
}

get_assets_summary() {
  jq -r '(.assets // []) | map(.name) | if length == 0 then "(none)" else join("\n") end' <<<"$1"
}

fetch_release_json() {
  local api_url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$api_url"
  else
    curl -fsSL "$api_url"
  fi
}

set_arch_vars() {
  local arch="${ARCH_OVERRIDE:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"
  case "$arch" in
    x86_64|amd64) ASSET_PATTERN="x86_64"; DEB_ARCH="amd64"; RPM_ARCH="x86_64" ;;
    aarch64|arm64) ASSET_PATTERN="arm64"; DEB_ARCH="arm64"; RPM_ARCH="aarch64" ;;
    *) ASSET_PATTERN="$arch"; DEB_ARCH="$arch"; RPM_ARCH="$arch" ;;
  esac
  ARCH="$arch"
}

resolve_tarball_url() {
  local json="$1"
  local url=""

  url="$(jq -r --arg pat "$ASSET_PATTERN" '(.assets // [])[]
    | select(.name | test("linux"; "i"))
    | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
    | select(.name | test($pat; "i"))
    | .browser_download_url' <<<"$json" | head -n 1)"

  if [[ -z "$url" ]]; then
    url="$(jq -r '(.assets // [])[]
      | select(.name | test("linux"; "i"))
      | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
      | .browser_download_url' <<<"$json" | head -n 1)"
  fi

  echo "$url"
}

validate_release_json() {
  local json="$1"
  local tag_name
  local asset_count

  tag_name="$(jq -r '.tag_name // empty' <<<"$json")"
  if [[ -z "$tag_name" || "$tag_name" == "null" ]]; then
    err "Upstream release response is missing tag_name."
  fi

  asset_count="$(jq -r '(.assets // []) | length' <<<"$json")"
  if [[ "$asset_count" == "0" ]]; then
    err "Upstream release $tag_name has no assets. Available assets:\n$(get_assets_summary "$json")"
  fi
}

write_release_notes() {
  local json="$1"
  local outdir="$2"
  local tag_name="$3"
  local title
  local body

  title="$(jq -r '.name // ""' <<<"$json")"
  [[ -z "$title" ]] && title="$tag_name"
  body="$(jq -r '.body // ""' <<<"$json")"
  echo "$title" > "$outdir/release_title.txt"
  echo "$body" > "$outdir/release_notes.md"
}

setup_workdir() {
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
}

write_initial_preferences() {
  local target="$1"
  cat >"$target" <<EOF
{
  "homepage_is_newtabpage": true,
  "browser": {
    "show_home_button": true
  }
}
EOF
  chmod 644 "$target"
}

write_wrapper_script() {
  local target="$1"
  local bin_name="$2"
  cat >"$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/helium\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

# Custom flags (add your chrome://flags overrides here)
# Example: EXTRA_FLAGS="--force-dark-mode --enable-features=VaapiVideoDecoder"
EXTRA_FLAGS=""

exec /opt/helium/$bin_name \$EXTRA_FLAGS "\$@"
EOF
  chmod +x "$target"
}

write_apparmor_profile() {
  local target="$1"
  local bin_name="$2"
  cat >"$target" <<EOF
abi <abi/4.0>,
include <tunables/global>

/opt/helium/$bin_name flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/opt.helium.helium>
}
EOF
}

build_offline_packages() {
  local tarball_url="$1"
  local outdir="$2"

  log "Building Offline DEB..."
  local offline_root="$WORKDIR/offline_root"
  mkdir -p "$offline_root/opt/helium" "$offline_root/usr/bin" \
    "$offline_root/usr/share/applications" "$offline_root/usr/share/icons/hicolor/512x512/apps"

  log "Downloading Tarball..."
  local tarball_file="${tarball_url##*/}"
  local ext="${tarball_file##*.}"
  local tarball_path=""
  if [[ "$tarball_file" == *.tar.* ]]; then
    tarball_path="$WORKDIR/$tarball_file"
  else
    tarball_path="$WORKDIR/helium.tar.$ext"
  fi

  curl -fsSL "$tarball_url" -o "$tarball_path"
  tar -xf "$tarball_path" -C "$WORKDIR"

  local extracted_dir
  extracted_dir="$(find "$WORKDIR" -maxdepth 1 -type d -name "helium*" | head -n 1)"
  [[ -z "$extracted_dir" ]] && err "Could not find extracted directory."

  cp -a "$extracted_dir/"* "$offline_root/opt/helium/"
  chmod -R u+w "$offline_root/opt/helium"

  local bin_name
  if [[ -f "$offline_root/opt/helium/helium" ]]; then
    bin_name="helium"
  elif [[ -f "$offline_root/opt/helium/chrome" ]]; then
    bin_name="chrome"
  else
    bin_name="helium"
    log "Warning: Could not detect binary name, defaulting to helium."
  fi

  if [[ -f "$offline_root/opt/helium/helium.png" ]]; then
    cp "$offline_root/opt/helium/helium.png" \
      "$offline_root/usr/share/icons/hicolor/512x512/apps/helium.png"
  elif [[ -f "$offline_root/opt/helium/product_logo_256.png" ]]; then
    cp "$offline_root/opt/helium/product_logo_256.png" \
      "$offline_root/usr/share/icons/hicolor/512x512/apps/helium.png"
  fi

  write_initial_preferences "$offline_root/opt/helium/initial_preferences"

  write_wrapper_script "$offline_root/usr/bin/helium" "$bin_name"

  mkdir -p "$offline_root/etc/apparmor.d"
  write_apparmor_profile "$offline_root/etc/apparmor.d/opt.helium.helium" "$bin_name"

  cat >"$offline_root/usr/share/applications/helium.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Helium
Name[lt_LT]=Helium
Name[ru_RU]=Helium
Comment=Helium Browser
Comment[lt_LT]=Helium naršyklė
Comment[ru_RU]=Браузер Helium
Exec=/usr/bin/helium %U
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=helium
EOF

  package_deb "$offline_root" "$outdir"
  package_rpm "$offline_root" "$outdir"

  if [[ -f "$outdir/meta.env" ]]; then
     # shellcheck disable=SC1090
     source "$outdir/meta.env"
     if [[ -n "${FULL_DEB_FILENAME:-}" && -n "${FULL_RPM_FILENAME:-}" ]]; then
        (cd "$outdir" && sha256sum "$FULL_DEB_FILENAME" "$FULL_RPM_FILENAME" > SHA256SUMS)
     fi
  fi
  log "Done."
}

package_deb() {
  local offline_root="$1"
  local outdir="$2"
  local full_deb_name="${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"

  fpm -s dir -t deb \
    -n "$PACKAGE_NAME" \
    -v "$VERSION" \
    --after-install "$(dirname "${BASH_SOURCE[0]}")/resources/postinst.sh" \
    -a "$DEB_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "https://github.com/$UPSTREAM_REPO" \
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
  local offline_root="$1"
  local outdir="$2"
  local full_rpm_name="${PACKAGE_NAME}-${VERSION}-${RPM_ARCH}.rpm"

  fpm -s dir -t rpm \
    -n "$PACKAGE_NAME" \
    -v "$VERSION" \
    --after-install "$(dirname "${BASH_SOURCE[0]}")/resources/postinst.sh" \
    -a "$RPM_ARCH" \
    -m "Helium Packager <noreply@github.com>" \
    --url "https://github.com/$UPSTREAM_REPO" \
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
