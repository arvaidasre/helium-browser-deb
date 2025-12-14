#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
UPSTREAM_REPO="imputnet/helium-linux"
OUTDIR="dist"

# --- Helper Functions ---
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
  v="${v#v}"       # Remove leading 'v'
  v="${v// /}"     # Remove spaces
  v="${v//_/.}"    # Replace underscores with dots
  echo "$v"
}

# --- Main Logic ---

check_deps

mkdir -p "$OUTDIR"

# 1. Fetch Upstream Release Info
log "Fetching latest release info from $UPSTREAM_REPO..."
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
JSON="$(curl -fsSL "$API_URL")"

TAG="$(jq -r '.tag_name' <<<"$JSON")"
[[ "$TAG" == "null" || -z "$TAG" ]] && err "Could not determine tag name."

VERSION="$(normalize_version "$TAG")"
log "Latest version: $VERSION (Tag: $TAG)"

# 2. Check if we should skip (CI only)
SKIPPED="0"
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  log "Checking if release $TAG exists in $GITHUB_REPOSITORY..."
  HTTP_CODE="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}")"
  
  if [[ "$HTTP_CODE" == "200" ]]; then
    log "Release $TAG already exists. Skipping build."
    SKIPPED="1"
  fi
fi

# Save metadata for GitHub Actions
cat >"$OUTDIR/meta.env" <<EOF
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=${SKIPPED}
EOF

if [[ "$SKIPPED" == "1" ]]; then
  exit 0
fi

# 3. Get Assets URLs
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
  x86_64|amd64) ASSET_PATTERN="x86_64"; DEB_ARCH="amd64" ;;
  aarch64|arm64) ASSET_PATTERN="arm64"; DEB_ARCH="arm64" ;;
  *) ASSET_PATTERN="$ARCH"; DEB_ARCH="$ARCH" ;;
esac

log "Target Architecture: $DEB_ARCH (Pattern: $ASSET_PATTERN)"

APPIMAGE_URL="$(jq -r --arg pat "$ASSET_PATTERN" '.assets[] | select(.name | test("\\.AppImage$")) | select(.name | test($pat)) | .browser_download_url' <<<"$JSON" | head -n 1)"
TARBALL_URL="$(jq -r --arg pat "$ASSET_PATTERN" '.assets[] | select(.name | test("_linux\\.tar\\.xz$")) | select(.name | test($pat)) | .browser_download_url' <<<"$JSON" | head -n 1)"

# Fallbacks
if [[ -z "$APPIMAGE_URL" ]]; then
  APPIMAGE_URL="$(jq -r '.assets[] | select(.name | test("\\.AppImage$")) | .browser_download_url' <<<"$JSON" | head -n 1)"
fi
if [[ -z "$TARBALL_URL" ]]; then
  TARBALL_URL="$(jq -r '.assets[] | select(.name | test("_linux\\.tar\\.xz$")) | .browser_download_url' <<<"$JSON" | head -n 1)"
fi

[[ -z "$APPIMAGE_URL" ]] && err "AppImage asset not found."
[[ -z "$TARBALL_URL" ]] && err "Tarball asset not found."

log "AppImage: $APPIMAGE_URL"
log "Tarball: $TARBALL_URL"

# Save Release Notes
TITLE="$(jq -r '.name // ""' <<<"$JSON")"
[[ -z "$TITLE" ]] && TITLE="$TAG"
BODY="$(jq -r '.body // ""' <<<"$JSON")"
echo "$TITLE" > "$OUTDIR/release_title.txt"
echo "$BODY" > "$OUTDIR/release_notes.md"

# 4. Prepare Build Environment
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- Build Offline DEB ---
log "Building Offline DEB..."
OFFLINE_ROOT="$WORKDIR/offline_root"
mkdir -p "$OFFLINE_ROOT/opt/helium" "$OFFLINE_ROOT/usr/bin" "$OFFLINE_ROOT/usr/share/applications" "$OFFLINE_ROOT/usr/share/icons/hicolor/512x512/apps"

# Download and Extract AppImage
log "Downloading AppImage..."
curl -fsSL "$APPIMAGE_URL" -o "$WORKDIR/appimage"
chmod +x "$WORKDIR/appimage"
(cd "$WORKDIR" && ./appimage --appimage-extract >/dev/null)

# Copy files
cp -a "$WORKDIR/squashfs-root/"* "$OFFLINE_ROOT/opt/helium/"
chmod -R u+w "$OFFLINE_ROOT/opt/helium" # Ensure writable for cleanup if needed

# Icon
if [[ -f "$OFFLINE_ROOT/opt/helium/helium.png" ]]; then
  cp "$OFFLINE_ROOT/opt/helium/helium.png" "$OFFLINE_ROOT/usr/share/icons/hicolor/512x512/apps/helium.png"
fi

# Wrapper Script
cat >"$OFFLINE_ROOT/usr/bin/helium" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export APPIMAGE="/opt/helium/AppRun" # Fake AppImage path for some apps
exec /opt/helium/AppRun "$@"
EOF
chmod +x "$OFFLINE_ROOT/usr/bin/helium"

# Desktop File
cat >"$OFFLINE_ROOT/usr/share/applications/helium.desktop" <<EOF
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

# Build with FPM
FULL_DEB_NAME="${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
fpm -s dir -t deb \
  -n "$PACKAGE_NAME" \
  -v "$VERSION" \
  --after-install "$(dirname "$0")/postinst.sh" \
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
  --package "$OUTDIR/$FULL_DEB_NAME" \
  -C "$OFFLINE_ROOT" .

log "Built: $OUTDIR/$FULL_DEB_NAME"

# --- Finalize ---
echo "FULL_DEB_FILENAME=$FULL_DEB_NAME" >> "$OUTDIR/meta.env"

cd "$OUTDIR"
sha256sum "$FULL_DEB_NAME" > SHA256SUMS
log "Done."
