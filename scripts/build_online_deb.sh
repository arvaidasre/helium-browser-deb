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
deb_filename=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarball-url) tarball_url="$2"; shift 2;;
    --version) version="$2"; shift 2;;
    --outdir) outdir="$2"; shift 2;;
    --package) package_name="$2"; shift 2;;
    --arch) arch="$2"; shift 2;;
    --deb-filename) deb_filename="$2"; shift 2;;
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

if [[ -z "$deb_filename" ]]; then
  deb_filename="${package_name}_${version}_${arch}.deb"
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

custom_ntp_url="https://google.com/"

# AppArmor bootstrap for Ubuntu 23.10+ (unprivileged userns restrictions)
THIS="$(readlink -f "$0" 2>/dev/null || echo "$0")"
export APPIMAGE="${APPIMAGE:-$THIS}"

AA_PROFILE_PATH=/etc/apparmor.d/helium-appimage
AA_SYSFS_USERNS_PATH=/proc/sys/kernel/apparmor_restrict_unprivileged_userns

has_command() {
  command -v "$1" >/dev/null 2>&1
}

sudo_shim() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  elif has_command pkexec; then
    exec pkexec "$@"
  elif has_command sudo; then
    exec sudo "$@"
  elif has_command su; then
    exec su -c "$*"
  else
    return 1
  fi
}

print_apparmor_profile() {
  local appimage_esc
  appimage_esc=$(echo "$APPIMAGE" | sed 's/"/\\"/g' | tr -d '\n')

  echo 'abi <abi/4.0>,'
  echo 'include <tunables/global>'
  echo
  echo 'profile helium-appimage "'"$appimage_esc"'" flags=(default_allow) {'
  echo '  userns,'
  echo '  include if exists <local/helium-appimage>'
  echo '}'
}

needs_apparmor_bootstrap() {
  [[ "${APPARMOR_BOOTSTRAPPED:-0}" != "1" ]] \
    && [[ -f "$AA_SYSFS_USERNS_PATH" ]] \
    && [[ "$(cat "$AA_SYSFS_USERNS_PATH" 2>/dev/null || echo 0)" != "0" ]] \
    && has_command aa-enabled \
    && [[ "$(aa-enabled 2>/dev/null || true)" == "Yes" ]] \
    && [[ -d /etc/apparmor.d ]] \
    && {
      [[ ! -f "$AA_PROFILE_PATH" ]] \
        || [[ "$(print_apparmor_profile)" != "$(cat "$AA_PROFILE_PATH")" ]]
    }
}

has_apparmor_prereqs() {
  if ! has_command apparmor_parser; then
    echo "WARN: Skipping AppArmor bootstrap due to missing apparmor_parser" >&2
    return 1
  fi
}

if needs_apparmor_bootstrap && has_apparmor_prereqs; then
  echo "Helium has detected that your system uses AppArmor." >&2
  echo "Before Helium can run, it needs to create an AppArmor profile for itself." >&2
  echo "It will request to run commands as root. If you do not wish to do this, please exit." >&2

  print_apparmor_profile | sudo_shim tee "$AA_PROFILE_PATH" >/dev/null \
    && sudo_shim chmod 644 "$AA_PROFILE_PATH" \
    && sudo_shim apparmor_parser -r "$AA_PROFILE_PATH" \
    && APPARMOR_BOOTSTRAPPED=1 exec "$APPIMAGE" "$@"
fi

has_custom_ntp=0
for arg in "$@"; do
  case "$arg" in
    --custom-ntp|--custom-ntp=*)
      has_custom_ntp=1
      break
      ;;
  esac
done

extra_args=()
if [[ "$has_custom_ntp" -eq 0 ]]; then
  extra_args+=("--custom-ntp=${custom_ntp_url}")
fi

# Last-resort crash avoidance: if userns is restricted and we couldn't
# bootstrap AppArmor, Chromium will fail with "No usable sandbox".
needs_no_sandbox=0
if [[ -r "$AA_SYSFS_USERNS_PATH" ]]; then
  if [[ "$(cat "$AA_SYSFS_USERNS_PATH" 2>/dev/null || echo 0)" != "0" ]]; then
    if ! has_command apparmor_parser; then
      needs_no_sandbox=1
    fi
  fi
fi

has_no_sandbox=0
for arg in "$@"; do
  if [[ "$arg" == "--no-sandbox" ]]; then
    has_no_sandbox=1
    break
  fi
done

if [[ "$needs_no_sandbox" -eq 1 && "$has_no_sandbox" -eq 0 ]]; then
  extra_args+=("--no-sandbox")
fi

exec /opt/helium/chrome "${extra_args[@]}" "$@"
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

# Seed first-run defaults for new profiles (do not overwrite if present)
if [[ ! -f "\${INSTALL_DIR}/master_preferences" ]]; then
  cat >"\${INSTALL_DIR}/master_preferences" <<'PREFS'
{
  "browser": {
    "enabled_labs_experiments": [
      "custom-ntp@https://google.com/"
    ]
  }
}
PREFS
fi

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
Provides: helium
Conflicts: helium
Replaces: helium
Description: Helium Browser (online installer)
 This package downloads the official Helium Linux build during install/upgrade
 and installs it into /opt/helium.
EOF

outdeb="$outdir/${deb_filename}"

dpkg-deb --build "$pkgroot" "$outdeb" >/dev/null

(
  cd "$outdir"
  sha256sum "$(basename "$outdeb")" > SHA256SUMS
)

echo "Built: $outdeb"
