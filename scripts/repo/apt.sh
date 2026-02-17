#!/usr/bin/env bash
# ==============================================================================
# apt.sh — Generate an APT repository from packages in dist/
# ==============================================================================
# Usage: ./apt.sh [REPO_DIR]
#
# Publishes the same pool under multiple APT distributions so users can specify
# their system codename (noble, jammy, etc.) while keeping a single pool.
# Override in CI: APT_DISTS="stable noble jammy" ./scripts/repo/apt.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="APT-REPO"

readonly REPO_DIR="${1:-site/public/apt}"
readonly APT_DISTS_DEFAULT=(stable noble jammy focal bookworm bullseye)

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps dpkg-scanpackages gzip

# ── Resolve dist list ─────────────────────────────────────────────────────────

if [[ -n "${APT_DISTS:-}" ]]; then
  # shellcheck disable=SC2206
  APT_DISTS=($APT_DISTS)
else
  APT_DISTS=("${APT_DISTS_DEFAULT[@]}")
fi

# ── Directory structure ───────────────────────────────────────────────────────

log "Generating APT repository in $REPO_DIR..."

mkdir -p "$REPO_DIR/dists/stable/main/binary-amd64" \
         "$REPO_DIR/dists/stable/main/binary-arm64" \
         "$REPO_DIR/pool/main"

# Copy .deb files from dist/
[[ -d "dist" ]] || err "dist/ directory not found."

for deb in dist/*.deb; do
  [[ -f "$deb" ]] || continue
  log "Copying $(basename "$deb") to pool..."
  cp "$deb" "$REPO_DIR/pool/main/"
done

# Ensure both architectures are present
ls -A "$REPO_DIR/pool/main"/*amd64*.deb  >/dev/null 2>&1 \
  || ls -A "$REPO_DIR/pool/main"/*x86_64*.deb >/dev/null 2>&1 \
  || err "No amd64 .deb packages found."

ls -A "$REPO_DIR/pool/main"/*arm64*.deb  >/dev/null 2>&1 \
  || ls -A "$REPO_DIR/pool/main"/*aarch64*.deb >/dev/null 2>&1 \
  || err "No arm64 .deb packages found."

# ── Generate Packages ────────────────────────────────────────────────────────

cd "$REPO_DIR"

for arch_pair in "amd64:amd64|x86_64" "arm64:arm64|aarch64"; do
  arch="${arch_pair%%:*}"
  pattern="${arch_pair#*:}"

  log "Generating $arch Packages..."
  dpkg-scanpackages --multiversion pool/main 2>/dev/null \
    | awk -v RS='' -v ORS='\n\n' "\$0 ~ /^Package:/ && /Architecture: ($pattern)/" \
    > "dists/stable/main/binary-$arch/Packages" || true

  if [[ -s "dists/stable/main/binary-$arch/Packages" ]]; then
    validate_packages_file "dists/stable/main/binary-$arch/Packages"
    gzip -k -f "dists/stable/main/binary-$arch/Packages" || err "Failed to gzip $arch Packages"
  else
    err "No $arch packages found in pool/main"
  fi
done

# Optional Sources file
if dpkg-scansources pool/main > "dists/stable/main/Sources" 2>/dev/null; then
  gzip -k -f "dists/stable/main/Sources" 2>/dev/null || warn "Failed to gzip Sources"
else
  warn "Sources generation skipped (optional)"
fi

# ── Release file ──────────────────────────────────────────────────────────────

log "Generating Release file..."
release_date="$(LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S %Z')"

cat > "dists/stable/Release" <<RELEASE
Origin: ${HELIUM_PACKAGE_NAME}
Label: ${HELIUM_PACKAGE_NAME}
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Helium Browser Repository
Date: ${release_date}
RELEASE

{
  echo "MD5Sum:"
  for f in dists/stable/main/binary-*/Packages* dists/stable/main/Sources*; do
    [[ -f "$f" ]] || continue
    printf " %s %8s %s\n" \
      "$(md5sum "$f" | cut -d' ' -f1)" \
      "$(file_size "$f")" \
      "${f#dists/stable/}"
  done
  echo "SHA256:"
  for f in dists/stable/main/binary-*/Packages* dists/stable/main/Sources*; do
    [[ -f "$f" ]] || continue
    printf " %s %8s %s\n" \
      "$(sha256sum "$f" | cut -d' ' -f1)" \
      "$(file_size "$f")" \
      "${f#dists/stable/}"
  done
} >> "dists/stable/Release"

# ── Distribution aliases ─────────────────────────────────────────────────────

log "Publishing distributions: ${APT_DISTS[*]}"
for dist in "${APT_DISTS[@]}"; do
  [[ "$dist" == "stable" ]] && continue
  rm -rf "dists/$dist"
  mkdir -p "dists/$dist"
  cp -a "dists/stable/"* "dists/$dist/"
  if [[ -f "dists/$dist/Release" ]]; then
    sed -i \
      -e "s/^Suite: .*/Suite: $dist/" \
      -e "s/^Codename: .*/Codename: $dist/" \
      "dists/$dist/Release"
  fi
done

log "APT repository generated: $REPO_DIR"
log "Usage: deb [arch=amd64,arm64] ${HELIUM_REPO_URL}/apt <codename|stable> main"
