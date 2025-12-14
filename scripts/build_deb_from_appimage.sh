#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_deb_from_appimage.sh --appimage <path> --version <version> --outdir <dir> [--package <name>] [--arch <arch>]

Notes:
  - Installs app files to /opt/helium
  - Provides launcher: /usr/bin/helium
EOF
}

appimage=""
version=""
outdir=""
package_name="helium-browser"
arch=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appimage) appimage="$2"; shift 2;;
    --version) version="$2"; shift 2;;
    --outdir) outdir="$2"; shift 2;;
    --package) package_name="$2"; shift 2;;
    --arch) arch="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$appimage" || -z "$version" || -z "$outdir" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$appimage" ]]; then
  echo "AppImage not found: $appimage" >&2
  exit 2
fi

normalize_version() {
  # Drop leading 'v' and normalize Debian version (keep simple)
  local v="$1"
  v="${v#v}"
  # Replace invalid chars with dots or dashes
  v="${v// /}"
  v="${v//_/.}"
  echo "$v"
}

infer_arch() {
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
    return
  fi
  local u
  u="$(uname -m)"
  case "$u" in
    x86_64) echo amd64;;
    aarch64|arm64) echo arm64;;
    armv7l|armhf) echo armhf;;
    *) echo "$u";;
  esac
}

version="$(normalize_version "$version")"
if [[ -z "$arch" ]]; then
  arch="$(infer_arch)"
fi

mkdir -p "$outdir"

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

extract_dir="$workdir/extract"
mkdir -p "$extract_dir"

chmod +x "$appimage"
(
  cd "$extract_dir"
  "$appimage" --appimage-extract >/dev/null
)

if [[ ! -d "$extract_dir/squashfs-root" ]]; then
  echo "Extraction failed: missing squashfs-root" >&2
  exit 1
fi

pkgroot="$workdir/pkgroot"
mkdir -p "$pkgroot/DEBIAN" "$pkgroot/opt/helium" "$pkgroot/usr/bin" "$pkgroot/usr/share/applications"

# Copy extracted payload
cp -a "$extract_dir/squashfs-root"/* "$pkgroot/opt/helium/"

# Wrapper
cat >"$pkgroot/usr/bin/helium" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /opt/helium/AppRun "$@"
EOF
chmod 0755 "$pkgroot/usr/bin/helium"

# Desktop entry
cat >"$pkgroot/usr/share/applications/helium.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Helium
Comment=Helium Browser
Exec=/usr/bin/helium %U
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=helium
EOF

# Icon (best-effort)
icon_src=""
for candidate in \
  "$extract_dir/squashfs-root/helium.png" \
  "$extract_dir/squashfs-root/usr/share/icons/hicolor/512x512/apps/helium.png" \
  "$extract_dir/squashfs-root/usr/share/pixmaps/helium.png"; do
  if [[ -f "$candidate" ]]; then
    icon_src="$candidate"
    break
  fi
done

if [[ -n "$icon_src" ]]; then
  mkdir -p "$pkgroot/usr/share/icons/hicolor/512x512/apps"
  cp -a "$icon_src" "$pkgroot/usr/share/icons/hicolor/512x512/apps/helium.png"
fi

installed_size_kb="$(du -sk "$pkgroot/opt/helium" | awk '{print $1}')"

# Control file
cat >"$pkgroot/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${version}
Section: web
Priority: optional
Architecture: ${arch}
Maintainer: Helium DEB repack <noreply@users.noreply.github.com>
Homepage: https://github.com/imputnet/helium-linux
Installed-Size: ${installed_size_kb}
Depends: ca-certificates, libgtk-3-0, libnss3, libxss1, libasound2, libgbm1
Description: Helium Browser (repacked from upstream AppImage)
 This package repacks the official Helium AppImage into a Debian package.
EOF

outdeb="$outdir/${package_name}_${version}_${arch}.deb"

dpkg-deb --build "$pkgroot" "$outdeb" >/dev/null

(
  cd "$outdir"
  sha256sum "$(basename "$outdeb")" > SHA256SUMS
)

echo "Built: $outdeb"
