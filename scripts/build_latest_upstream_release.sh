#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_latest_upstream_release.sh --outdir <dir> [--package <name>] [--upstream <owner/repo>]

Behavior:
  - Finds the latest upstream GitHub Release
  - Builds a full offline .deb from upstream AppImage (for GitHub Releases)
  - Builds a small online-installer .deb (for GitHub Pages APT repo)
  - If running in GitHub Actions and a Release with the same tag already exists in this repo, it will skip.

Outputs:
  Writes --outdir/meta.env with:
    UPSTREAM_TAG, UPSTREAM_VERSION, APPIMAGE_URL, TARBALL_URL, SKIPPED,
    FULL_DEB_FILENAME, ONLINE_DEB_FILENAME
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

# Upstream release title/body (for mirroring release notes)
upstream_title="$(jq -r '.name // ""' <<<"$json")"
if [[ -z "$upstream_title" || "$upstream_title" == "null" ]]; then
  upstream_title="$tag"
fi
upstream_body="$(jq -r '.body // ""' <<<"$json")"

# Some repos rely on GitHub auto-generated release notes, which may not be stored
# in the release body. If body is empty, attempt to generate notes via API.
if [[ -z "$upstream_body" ]]; then
  api_auth_header=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    api_auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  prev_tag="$(curl -fsSL "https://api.github.com/repos/${upstream_repo}/releases?per_page=2" \
    | jq -r '.[1].tag_name // ""')"

  gen_payload="$(jq -n --arg tag "$tag" --arg prev "$prev_tag" 'if ($prev|length) > 0 then {tag_name:$tag, previous_tag_name:$prev} else {tag_name:$tag} end')"
  upstream_body="$(curl -fsSL \
    -X POST \
    -H 'Content-Type: application/json' \
    "${api_auth_header[@]}" \
    -d "$gen_payload" \
    "https://api.github.com/repos/${upstream_repo}/releases/generate-notes" \
    | jq -r '.body // ""' \
    || true)"
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

tarball_url="$(jq -r --arg pat "$asset_arch_pat" '.assets[]
  | select(.name | test("_linux\\.tar\\.xz$"))
  | select(.name | test($pat))
  | .browser_download_url' <<<"$json" | head -n 1)"

# Fallback: any linux tarball if arch-specific match is missing
if [[ -z "$tarball_url" || "$tarball_url" == "null" ]]; then
  tarball_url="$(jq -r '.assets[] | select(.name | test("_linux\\.tar\\.xz$")) | .browser_download_url' <<<"$json" | head -n 1)"
fi
if [[ -z "$tarball_url" || "$tarball_url" == "null" ]]; then
  echo "No linux tarball asset found in upstream latest release ($tag)" >&2
  exit 1
fi

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
TARBALL_URL=${tarball_url}
SKIPPED=${skipped}
FULL_DEB_FILENAME=${package_name}_${version}_ARCH.deb
ONLINE_DEB_FILENAME=${package_name}-online_${version}_ARCH.deb
EOF

# Write release title/notes files (used by workflow)
printf '%s' "$upstream_title" > "$outdir/release_title.txt"
printf '%s\n' "$upstream_body" > "$outdir/release_notes.md"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine architecture once for filenames
arch="$(dpkg --print-architecture 2>/dev/null || true)"
if [[ -z "$arch" ]]; then arch="amd64"; fi

if [[ "$skipped" == "1" ]]; then
  echo "Release ${tag} already exists in ${this_repo}; skipping build."
  exit 0
fi

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

# Build full offline DEB
appimage_path="$workdir/Helium-${tag}.AppImage"
curl -fL "$appimage_url" -o "$appimage_path"

"$scripts_dir/build_deb_from_appimage.sh" \
  --appimage "$appimage_path" \
  --version "$version" \
  --outdir "$outdir" \
  --package "$package_name"

full_deb_path="$(ls -1 "$outdir/${package_name}_${version}_"*.deb 2>/dev/null | head -n 1)"
if [[ -z "$full_deb_path" ]]; then
  echo "Failed to locate built full DEB in: $outdir" >&2
  exit 1
fi

# Build small online-installer DEB (for APT repo)
"$scripts_dir/build_online_deb.sh" \
  --tarball-url "$tarball_url" \
  --version "$version" \
  --outdir "$outdir" \
  --package "${package_name}" \
  --deb-filename "${package_name}-online_${version}_${arch}.deb"

# Update meta.env with real filenames
sed -i "s/FULL_DEB_FILENAME=.*/FULL_DEB_FILENAME=${package_name}_${version}_${arch}.deb/" "$outdir/meta.env"
sed -i "s/ONLINE_DEB_FILENAME=.*/ONLINE_DEB_FILENAME=${package_name}-online_${version}_${arch}.deb/" "$outdir/meta.env"

# Build checksums for the full offline DEB (for Releases)
(
  cd "$outdir"
  sha256sum "${package_name}_${version}_${arch}.deb" > SHA256SUMS
)

echo "Done. Tag: $tag"
