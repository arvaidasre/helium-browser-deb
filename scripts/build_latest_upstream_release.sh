#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_latest_upstream_release.sh --outdir <dir> [--package <name>] [--upstream <owner/repo>]

Behavior:
  - Finds the latest upstream GitHub Release
  - Downloads the first *.AppImage asset
  - Builds a .deb and SHA256SUMS into --outdir
  - If running in GitHub Actions and a Release with the same tag already exists in this repo, it will skip.

Outputs:
  Writes --outdir/meta.env with:
    UPSTREAM_TAG, UPSTREAM_VERSION, APPIMAGE_URL, SKIPPED, DEB_FILENAME
EOF
}

outdir=""
package_name="helium-browser"
upstream_repo="imputnet/helium-linux"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --outdir) outdir="$2"; shift 2;;
    --package) package_name="$2"; shift 2;;
    --upstream) upstream_repo="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$outdir" ]]; then
  usage
  exit 2
fi

mkdir -p "$outdir"

api="https://api.github.com/repos/${upstream_repo}/releases/latest"
json="$(curl -fsSL "$api")"

tag="$(jq -r '.tag_name' <<<"$json")"
if [[ -z "$tag" || "$tag" == "null" ]]; then
  echo "Failed to read tag_name from upstream latest release" >&2
  exit 1
fi

host_arch="$(dpkg --print-architecture 2>/dev/null || true)"
if [[ -z "$host_arch" ]]; then
  host_arch="amd64"
fi

case "$host_arch" in
  amd64) asset_arch_pat="x86_64";;
  arm64) asset_arch_pat="arm64";;
  *) asset_arch_pat="$host_arch";;
esac

appimage_url="$(jq -r --arg pat "$asset_arch_pat" '.assets[]
  | select(.name | test("\\.AppImage$"))
  | select(.name | test($pat))
  | .browser_download_url' <<<"$json" | head -n 1)"

# Fallback: any AppImage if arch-specific match is missing
if [[ -z "$appimage_url" || "$appimage_url" == "null" ]]; then
  appimage_url="$(jq -r '.assets[] | select(.name | test("\\.AppImage$")) | .browser_download_url' <<<"$json" | head -n 1)"
fi
if [[ -z "$appimage_url" || "$appimage_url" == "null" ]]; then
  echo "No AppImage asset found in upstream latest release ($tag)" >&2
  exit 1
fi

normalize_version() {
  local v="$1"
  v="${v#v}"
  echo "$v"
}

version="$(normalize_version "$tag")"

# Optional: skip if release already exists in THIS repo (when running in CI)
# Uses GitHub API because it does not require gh CLI.
this_repo="${GITHUB_REPOSITORY:-}"
token="${GITHUB_TOKEN:-}"
skipped="0"

if [[ -n "$this_repo" && -n "$token" ]]; then
  status_code="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${this_repo}/releases/tags/${tag}")"
  if [[ "$status_code" == "200" ]]; then
    skipped="1"
  fi
fi

# Write meta for workflow consumption
cat >"$outdir/meta.env" <<EOF
UPSTREAM_TAG=${tag}
UPSTREAM_VERSION=${version}
APPIMAGE_URL=${appimage_url}
SKIPPED=${skipped}
DEB_FILENAME=${package_name}_${version}_ARCH.deb
EOF

if [[ "$skipped" == "1" ]]; then
  echo "Release ${tag} already exists in ${this_repo}; skipping build."
  exit 0
fi

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

appimage_path="$workdir/Helium-${tag}.AppImage"
curl -fL "$appimage_url" -o "$appimage_path"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$scripts_dir/build_deb_from_appimage.sh" \
  --appimage "$appimage_path" \
  --version "$version" \
  --outdir "$outdir" \
  --package "$package_name"

# Update meta.env with real filename
arch="$(dpkg --print-architecture 2>/dev/null || true)"
if [[ -z "$arch" ]]; then arch="amd64"; fi
sed -i "s/DEB_FILENAME=.*/DEB_FILENAME=${package_name}_${version}_${arch}.deb/" "$outdir/meta.env"

echo "Done. Tag: $tag"
