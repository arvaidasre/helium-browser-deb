#!/usr/bin/env bash
set -euo pipefail

APT_DIR="${1:-repo/apt}"
RPM_DIR="${2:-repo/rpm}"

die() {
  echo "[validate] ERROR: $*" >&2
  exit 1
}

require_file() {
  local f="$1"
  [[ -f "$f" ]] || die "Missing file: $f"
}

require_grep() {
  local f="$1"
  local pat="$2"
  grep -qE "$pat" "$f" || die "Expected pattern '$pat' in $f"
}

echo "[validate] Checking APT repo: $APT_DIR"
require_file "$APT_DIR/dists/stable/Release"
require_grep "$APT_DIR/dists/stable/Release" '^Architectures: '
require_grep "$APT_DIR/dists/stable/Release" '^Components: '
require_file "$APT_DIR/dists/stable/main/binary-amd64/Packages"
require_file "$APT_DIR/dists/stable/main/binary-amd64/Packages.gz"
require_file "$APT_DIR/dists/stable/main/binary-arm64/Packages"
require_file "$APT_DIR/dists/stable/main/binary-arm64/Packages.gz"

# We publish stable plus common distro codenames as aliases.
for dist in noble jammy focal bookworm bullseye; do
  require_file "$APT_DIR/dists/$dist/Release"
done

echo "[validate] Checking RPM repo: $RPM_DIR"
require_file "$RPM_DIR/x86_64/repodata/repomd.xml"
require_file "$RPM_DIR/aarch64/repodata/repomd.xml"
require_grep "$RPM_DIR/x86_64/repodata/repomd.xml" '<repomd'
require_grep "$RPM_DIR/aarch64/repodata/repomd.xml" '<repomd'

echo "[validate] OK"
