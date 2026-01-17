#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
PACKAGE_NAME="helium-browser"
UPSTREAM_REPO="imputnet/helium-linux"
OUTDIR="dist"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[BUILD]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

curl_retry() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused "$@"
}

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

get_assets_summary() {
  jq -r '(.assets // []) | map(.name) | if length == 0 then "(none)" else join("\n") end' <<<"$1"
}

# --- Main Logic ---

check_deps

mkdir -p "$OUTDIR"

# 1. Fetch Upstream Release Info
log "Fetching latest release info from $UPSTREAM_REPO..."
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
JSON="$(curl_retry "$API_URL")"

TAG="$(jq -r '.tag_name' <<<"$JSON")"
[[ "$TAG" == "null" || -z "$TAG" ]] && err "Could not determine tag name."

VERSION="$(normalize_version "$TAG")"
log "Latest version: $VERSION (Tag: $TAG)"

# Check if this is a pre-release
PRERELEASE="$(jq -r '.prerelease // false' <<<"$JSON")"
if [[ "$PRERELEASE" == "true" || "$TAG" =~ (alpha|beta|rc|pre|preview) ]]; then
  IS_PRERELEASE="true"
  log "Detected pre-release: $TAG"
else
  IS_PRERELEASE="false"
fi

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

  # Check creation date of upstream release - don't build releases older than 2025-01-01
  UPSTREAM_CREATED_AT="$(jq -r '.created_at' <<<"$JSON")"
  log "Upstream release created at: $UPSTREAM_CREATED_AT"
  if [[ "$UPSTREAM_CREATED_AT" < "2025-01-01" ]]; then
    log "Upstream release is too old (pre-2025). Skipping."
    SKIPPED="1"
  fi
fi

# Save metadata for GitHub Actions
cat >"$OUTDIR/meta.env" <<EOF
UPSTREAM_TAG=${TAG}
UPSTREAM_VERSION=${VERSION}
SKIPPED=${SKIPPED}
IS_PRERELEASE=${IS_PRERELEASE}
EOF

if [[ "$SKIPPED" == "1" ]]; then
  exit 0
fi

# 3. Get Assets URLs
ARCH="${ARCH_OVERRIDE:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"
case "$ARCH" in
  x86_64|amd64) ASSET_PATTERN="x86_64"; DEB_ARCH="amd64"; RPM_ARCH="x86_64" ;;
  aarch64|arm64) ASSET_PATTERN="arm64"; DEB_ARCH="arm64"; RPM_ARCH="aarch64" ;;
  *) ASSET_PATTERN="$ARCH"; DEB_ARCH="$ARCH"; RPM_ARCH="$ARCH" ;;
esac

log "Target Architecture: DEB=$DEB_ARCH, RPM=$RPM_ARCH (Pattern: $ASSET_PATTERN)"

ASSET_COUNT="$(jq -r '(.assets // []) | length' <<<"$JSON")"
if [[ "$ASSET_COUNT" == "0" ]]; then
  err "Upstream release $TAG has no assets. Available assets:\n$(get_assets_summary "$JSON")"
fi

TARBALL_URL="$(jq -r --arg pat "$ASSET_PATTERN" '(.assets // [])[]
  | select(.name | test("linux"; "i"))
  | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
  | select(.name | test($pat; "i"))
  | .browser_download_url' <<<"$JSON" | head -n 1)"

# Fallbacks
if [[ -z "$TARBALL_URL" ]]; then
  TARBALL_URL="$(jq -r '(.assets // [])[]
    | select(.name | test("linux"; "i"))
    | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
    | .browser_download_url' <<<"$JSON" | head -n 1)"
fi

if [[ -z "$TARBALL_URL" ]]; then
  err "Tarball asset not found for $TAG (arch pattern: $ASSET_PATTERN). Available assets:\n$(get_assets_summary "$JSON")"
fi

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

# Download and Extract Tarball
log "Downloading Tarball..."
TARBALL_FILE="${TARBALL_URL##*/}"
EXT="${TARBALL_FILE##*.}"
if [[ "$TARBALL_FILE" == *.tar.* ]]; then
  TARBALL_PATH="$WORKDIR/$TARBALL_FILE"
else
  TARBALL_PATH="$WORKDIR/helium.tar.$EXT"
fi

curl_retry "$TARBALL_URL" -o "$TARBALL_PATH"
tar -xf "$TARBALL_PATH" -C "$WORKDIR"

# Locate extracted directory
EXTRACTED_DIR="$(find "$WORKDIR" -maxdepth 1 -type d -name "helium*" | head -n 1)"
[[ -z "$EXTRACTED_DIR" ]] && err "Could not find extracted directory."

# Copy files
cp -a "$EXTRACTED_DIR/"* "$OFFLINE_ROOT/opt/helium/"
chmod -R u+w "$OFFLINE_ROOT/opt/helium"

# Determine binary name
if [[ -f "$OFFLINE_ROOT/opt/helium/helium" ]]; then
  BIN_NAME="helium"
elif [[ -f "$OFFLINE_ROOT/opt/helium/chrome" ]]; then
  BIN_NAME="chrome"
else
  BIN_NAME="helium"
  log "Warning: Could not detect binary name, defaulting to helium."
fi

# Icon
if [[ -f "$OFFLINE_ROOT/opt/helium/helium.png" ]]; then
  cp "$OFFLINE_ROOT/opt/helium/helium.png" "$OFFLINE_ROOT/usr/share/icons/hicolor/512x512/apps/helium.png"
elif [[ -f "$OFFLINE_ROOT/opt/helium/product_logo_256.png" ]]; then
   cp "$OFFLINE_ROOT/opt/helium/product_logo_256.png" "$OFFLINE_ROOT/usr/share/icons/hicolor/512x512/apps/helium.png"
fi

# Initial Preferences (Homepage & Startup)
cat >"$OFFLINE_ROOT/opt/helium/initial_preferences" <<EOF
{
  "homepage": "https://www.google.com",
  "homepage_is_newtabpage": false,
  "browser": {
    "show_home_button": true
  },
  "session": {
    "restore_on_startup": 4,
    "startup_urls": [
      "https://www.google.com"
    ]
  }
}
EOF
chmod 644 "$OFFLINE_ROOT/opt/helium/initial_preferences"

# Wrapper Script
cat >"$OFFLINE_ROOT/usr/bin/helium" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/helium\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

# Custom flags (add your chrome://flags overrides here)
# Example: EXTRA_FLAGS="--force-dark-mode --enable-features=VaapiVideoDecoder"
EXTRA_FLAGS="--custom-ntp=https://www.google.com"

exec /opt/helium/$BIN_NAME \$EXTRA_FLAGS "\$@"
EOF
chmod +x "$OFFLINE_ROOT/usr/bin/helium"
# AppArmor Profile (for Ubuntu 24.04+ user namespace restrictions)
mkdir -p "$OFFLINE_ROOT/etc/apparmor.d"
cat >"$OFFLINE_ROOT/etc/apparmor.d/opt.helium.helium" <<EOF
abi <abi/4.0>,
include <tunables/global>

/opt/helium/$BIN_NAME flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/opt.helium.helium>
}
EOF
# Desktop File
cat >"$OFFLINE_ROOT/usr/share/applications/helium.desktop" <<EOF
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

# Build with FPM (RPM)
FULL_RPM_NAME="${PACKAGE_NAME}-${VERSION}-${RPM_ARCH}.rpm"
fpm -s dir -t rpm \
  -n "$PACKAGE_NAME" \
  -v "$VERSION" \
  --after-install "$(dirname "$0")/postinst.sh" \
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
  --package "$OUTDIR/$FULL_RPM_NAME" \
  -C "$OFFLINE_ROOT" .

log "Built: $OUTDIR/$FULL_RPM_NAME"

# --- Finalize ---
echo "FULL_DEB_FILENAME=$FULL_DEB_NAME" >> "$OUTDIR/meta.env"
echo "FULL_RPM_FILENAME=$FULL_RPM_NAME" >> "$OUTDIR/meta.env"

cd "$OUTDIR"
sha256sum "$FULL_DEB_NAME" "$FULL_RPM_NAME" > SHA256SUMS
log "Done."
