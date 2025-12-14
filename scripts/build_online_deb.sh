#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_online_deb.sh --tarball-url <url> --version <version> --outdir <dir> [--package <name>] [--arch <arch>]

Builds a small DEB that downloads and installs Helium payload into /opt/helium
from the given upstream linux tar.xz URL during install/upgrade.
EOF
}

tarball_url=""
version=""
outdir=""
package_name="helium-browser"
arch=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarball-url) tarball_url="$2"; shift 2;;
    --version) version="$2"; shift 2;;
    --outdir) outdir="$2"; shift 2;;
    --package) package_name="$2"; shift 2;;
    --arch) arch="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$tarball_url" || -z "$version" || -z "$outdir" ]]; then
  usage
  exit 2
fi

normalize_version() {
  local v="$1"
  v="${v#v}"
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

pkgroot="$workdir/pkgroot"
mkdir -p "$pkgroot/DEBIAN" "$pkgroot/opt/helium" "$pkgroot/usr/bin" "$pkgroot/usr/share/applications"

# Wrapper
cat >"$pkgroot/usr/bin/helium" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /opt/helium/chrome "$@"
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

# postinst: download and install payload
cat >"$pkgroot/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TARBALL_URL="__TARBALL_URL__"
INSTALL_DIR="/opt/helium"

mkdir -p "${INSTALL_DIR}"

tmpdir="\$(mktemp -d)"
cleanup() { rm -rf "\${tmpdir}"; }
trap cleanup EXIT

curl -fL "\${TARBALL_URL}" -o "\${tmpdir}/helium.tar.xz"

# Extract into a temp directory first, then atomically replace
mkdir -p "\${tmpdir}/new"

tar -xJf "\${tmpdir}/helium.tar.xz" -C "\${tmpdir}/new" --strip-components=1

# Basic sanity: ensure main binary exists
if [[ ! -f "\${tmpdir}/new/chrome" ]]; then
  echo "Expected 'chrome' binary not found after extraction" >&2
  exit 1
fi

rm -rf "\${INSTALL_DIR}.old" "\${INSTALL_DIR}.new"
mkdir -p "\${INSTALL_DIR}.new"

# Move extracted payload into place
cp -a "\${tmpdir}/new"/. "\${INSTALL_DIR}.new/"

mv "\${INSTALL_DIR}" "\${INSTALL_DIR}.old" 2>/dev/null || true
mv "\${INSTALL_DIR}.new" "\${INSTALL_DIR}"
rm -rf "\${INSTALL_DIR}.old" || true

chmod +x "\${INSTALL_DIR}/chrome" || true

exit 0
EOF
chmod 0755 "$pkgroot/DEBIAN/postinst"

# Inject tarball URL (escape for sed)
tarball_url_escaped="$(printf '%s' "$tarball_url" | sed -e 's/[\\&]/\\\\&/g')"
sed -i "s|__TARBALL_URL__|${tarball_url_escaped}|" "$pkgroot/DEBIAN/postinst"

# postrm (purge): remove payload
cat >"$pkgroot/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "purge" ]]; then
  rm -rf /opt/helium
fi

exit 0
EOF
chmod 0755 "$pkgroot/DEBIAN/postrm"

installed_size_kb=64

cat >"$pkgroot/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${version}
Section: web
Priority: optional
Architecture: ${arch}
Maintainer: Helium DEB repack <noreply@users.noreply.github.com>
Homepage: https://github.com/imputnet/helium-linux
Installed-Size: ${installed_size_kb}
Depends: ca-certificates, curl, xz-utils, tar
Description: Helium Browser (online installer)
 This package downloads the official Helium Linux build during install/upgrade
 and installs it into /opt/helium.
EOF

outdeb="$outdir/${package_name}_${version}_${arch}.deb"

dpkg-deb --build "$pkgroot" "$outdeb" >/dev/null

(
  cd "$outdir"
  sha256sum "$(basename "$outdeb")" > SHA256SUMS
)

echo "Built: $outdeb"
