#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  update_apt_repo.sh --repo-dir <dir> --deb <path.deb> [--suite stable] [--component main]

Creates/updates a simple APT repository layout:
  <repo-dir>/pool/main/<first-letter>/<package>/<package>_<version>_<arch>.deb
  <repo-dir>/dists/<suite>/<component>/binary-<arch>/Packages(.gz)
  <repo-dir>/dists/<suite>/Release

Note:
  This repo is not signed. Users should use [trusted=yes] or add signing separately.
EOF
}

repo_dir=""
deb_path=""
suite="stable"
component="main"
url_base=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) repo_dir="$2"; shift 2;;
    --deb) deb_path="$2"; shift 2;;
    --suite) suite="$2"; shift 2;;
    --component) component="$2"; shift 2;;
    --url-base) url_base="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$repo_dir" || -z "$deb_path" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$deb_path" ]]; then
  echo "DEB not found: $deb_path" >&2
  exit 2
fi

pkg_name="$(dpkg-deb -f "$deb_path" Package)"
arch="$(dpkg-deb -f "$deb_path" Architecture)"

if [[ -z "$pkg_name" || -z "$arch" ]]; then
  echo "Failed to read Package/Architecture from: $deb_path" >&2
  exit 1
fi

first_letter="${pkg_name:0:1}"

pool_dir="$repo_dir/pool/$component/$first_letter/$pkg_name"
bin_dir="$repo_dir/dists/$suite/$component/binary-$arch"

pool_dir_rel="pool/$component/$first_letter/$pkg_name"
bin_dir_rel="dists/$suite/$component/binary-$arch"

mkdir -p "$pool_dir" "$bin_dir"

# Copy DEB into pool
cp -f "$deb_path" "$pool_dir/"

# Generate Packages index (scan whole pool)
(
  cd "$repo_dir"
  mkdir -p "$bin_dir_rel"
  dpkg-scanpackages -m "pool/$component" /dev/null > "$bin_dir_rel/Packages"
  gzip -9c "$bin_dir_rel/Packages" > "$bin_dir_rel/Packages.gz"
)

# Generate Release file if apt-ftparchive is available
if command -v apt-ftparchive >/dev/null 2>&1; then
  (
    cd "$repo_dir"
    apt-ftparchive release "dists/$suite" > "dists/$suite/Release"
  )
fi

echo "APT repo updated: $repo_dir (suite=$suite component=$component arch=$arch)"

if [[ -n "$url_base" ]]; then
  cat >"$repo_dir/setup.sh" <<EOF
#!/bin/bash
set -e

REPO_URL="${url_base}"
LIST_FILE="/etc/apt/sources.list.d/helium-browser.list"

if [ "\$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Adding Helium Browser repository..."
echo "deb [trusted=yes] \$REPO_URL $suite $component" > "\$LIST_FILE"

echo "Updating package lists..."
apt-get update

echo "Installing Helium Browser..."
apt-get install -y helium-browser

echo "Done! Helium Browser is installed."
EOF
  chmod +x "$repo_dir/setup.sh"
  echo "Generated setup.sh at $repo_dir/setup.sh"
fi
