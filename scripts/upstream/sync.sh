#!/usr/bin/env bash
# ==============================================================================
# sync.sh — Fetch upstream releases and create local metadata
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

LOG_PREFIX="SYNC"

readonly SYNC_DIR="${SYNC_DIR:-sync}"
readonly RELEASES_DIR="${RELEASES_DIR:-releases}"

# ── Dependencies ──────────────────────────────────────────────────────────────

check_deps curl jq git

# ── Fetch all releases (paginated) ───────────────────────────────────────────

fetch_releases() {
  log "Fetching releases from ${HELIUM_UPSTREAM_REPO}..."
  mkdir -p "$SYNC_DIR"

  local page=1 per_page=100 total=0 count

  while true; do
    log "Fetching page $page..."
    local url="https://api.github.com/repos/${HELIUM_UPSTREAM_REPO}/releases?page=${page}&per_page=${per_page}"
    local response
    response="$(github_api_get "$url")"

    [[ "$response" == "[]" ]] && break
    echo "$response" > "$SYNC_DIR/releases_page_${page}.json"

    count="$(jq 'length' <<<"$response")"
    total=$(( total + count ))
    log "Page $page: $count releases"

    (( count < per_page )) && break
    (( page++ ))
  done

  log "Total releases fetched: $total"
}

# ── Merge pages into one file ────────────────────────────────────────────────

merge_releases() {
  log "Merging into single file..."
  jq -s 'add' "$SYNC_DIR"/releases_page_*.json > "$SYNC_DIR/all_releases.json"
}

# ── Create per-release metadata ──────────────────────────────────────────────

process_releases() {
  log "Processing releases..."
  mkdir -p "$RELEASES_DIR"

  local merged="$SYNC_DIR/all_releases.json"
  local count
  count="$(jq 'length' "$merged")"

  for (( i = 0; i < count; i++ )); do
    local release
    release="$(jq ".[$i]" "$merged")"

    local tag name body created_at published_at prerelease draft author asset_count
    tag="$(jq -r '.tag_name'       <<<"$release")"
    name="$(jq -r '.name // .tag_name' <<<"$release")"
    body="$(jq -r '.body // ""'    <<<"$release")"
    created_at="$(jq -r '.created_at'  <<<"$release")"
    published_at="$(jq -r '.published_at' <<<"$release")"
    prerelease="$(jq -r '.prerelease'  <<<"$release")"
    draft="$(jq -r '.draft'        <<<"$release")"
    author="$(jq -r '.author.login'<<<"$release")"
    asset_count="$(jq '.assets | length' <<<"$release")"

    local rdir="$RELEASES_DIR/$tag"
    mkdir -p "$rdir"

    jq -n \
      --arg tag "$tag" --arg name "$name" --arg author "$author" \
      --arg created "$created_at" --arg published "$published_at" \
      --argjson pre "$prerelease" --argjson draft "$draft" \
      --argjson assets "$asset_count" \
      --arg url "${HELIUM_UPSTREAM_URL}/releases/tag/$tag" \
      '{tag:$tag,name:$name,author:$author,created_at:$created,
        published_at:$published,prerelease:$pre,draft:$draft,
        asset_count:$assets,upstream_url:$url}' \
      > "$rdir/metadata.json"

    echo "$body" > "$rdir/RELEASE_NOTES.md"
    jq '.assets[] | {name,size,download_count,browser_download_url}' \
      <<<"$release" > "$rdir/assets.json"

    log "Processed: $tag (author: $author, assets: $asset_count)"
  done
}

# ── Generate summary files ───────────────────────────────────────────────────

generate_sync_index() {
  log "Generating INDEX.md..."
  local ts
  ts="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"

  {
    echo "# Helium Browser Releases — Upstream Sync"
    echo ""
    echo "**Last synced:** $ts"
    echo "**Upstream:** [${HELIUM_UPSTREAM_REPO}](${HELIUM_UPSTREAM_URL})"
    echo ""
    echo "| Tag | Name | Author | Type | Assets | Date |"
    echo "|-----|------|--------|------|--------|------|"

    for rdir in "$RELEASES_DIR"/*/; do
      [[ -f "$rdir/metadata.json" ]] || continue
      local meta tag name author prerelease asset_count published_at type
      meta="$(cat "$rdir/metadata.json")"
      tag="$(jq -r '.tag'          <<<"$meta")"
      name="$(jq -r '.name'        <<<"$meta")"
      author="$(jq -r '.author'    <<<"$meta")"
      prerelease="$(jq -r '.prerelease' <<<"$meta")"
      asset_count="$(jq -r '.asset_count' <<<"$meta")"
      published_at="$(jq -r '.published_at' <<<"$meta" | cut -dT -f1)"
      type="Release"; [[ "$prerelease" == "true" ]] && type="Pre-release"
      echo "| [$tag](${HELIUM_UPSTREAM_URL}/releases/tag/$tag) | $name | $author | $type | $asset_count | $published_at |"
    done
  } > "$RELEASES_DIR/INDEX.md"
}

generate_changelog() {
  log "Generating CHANGELOG.md..."
  local ts
  ts="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"

  {
    echo "# Helium Browser — Complete Changelog"
    echo ""
    echo "**Synced from:** [${HELIUM_UPSTREAM_REPO}](${HELIUM_UPSTREAM_URL})"
    echo "**Last update:** $ts"
    echo ""
    echo "---"
    echo ""

    for rdir in $(ls -d "$RELEASES_DIR"/*/ 2>/dev/null | sort -r); do
      [[ -f "$rdir/metadata.json" ]] || continue
      local meta tag name author published_at prerelease upstream_url type=""
      meta="$(cat "$rdir/metadata.json")"
      tag="$(jq -r '.tag'             <<<"$meta")"
      name="$(jq -r '.name'           <<<"$meta")"
      author="$(jq -r '.author'       <<<"$meta")"
      published_at="$(jq -r '.published_at' <<<"$meta")"
      prerelease="$(jq -r '.prerelease' <<<"$meta")"
      upstream_url="$(jq -r '.upstream_url' <<<"$meta")"
      [[ "$prerelease" == "true" ]] && type=" (Pre-release)"

      echo "## [$tag]($upstream_url)$type"
      echo ""
      echo "**Author:** $author  "
      echo "**Published:** $published_at"
      echo ""

      if [[ -f "$rdir/RELEASE_NOTES.md" ]]; then
        cat "$rdir/RELEASE_NOTES.md"
      fi

      echo ""
      echo "---"
      echo ""
    done
  } > "$RELEASES_DIR/CHANGELOG.md"
}

# ── Create git tags ──────────────────────────────────────────────────────────

create_git_tags() {
  log "Creating git tags..."
  local created=0 skipped=0

  for rdir in "$RELEASES_DIR"/*/; do
    [[ -f "$rdir/metadata.json" ]] || continue
    local meta tag name author published_at body
    meta="$(cat "$rdir/metadata.json")"
    tag="$(jq -r '.tag' <<<"$meta")"

    if git rev-parse "$tag" >/dev/null 2>&1; then
      (( skipped++ )); continue
    fi

    name="$(jq -r '.name' <<<"$meta")"
    author="$(jq -r '.author' <<<"$meta")"
    published_at="$(jq -r '.published_at' <<<"$meta")"
    body="$(cat "$rdir/RELEASE_NOTES.md" 2>/dev/null || true)"

    git tag -a "$tag" -m "$name

Author: $author
Published: $published_at
Upstream: ${HELIUM_UPSTREAM_URL}/releases/tag/$tag

$body" 2>/dev/null || { warn "Could not create tag: $tag"; continue; }

    log "Created tag: $tag"
    (( created++ ))
  done

  log "Tags: created=$created skipped=$skipped"
  (( created > 0 )) && log "Push tags: git push origin --tags"
}

# ── Summary ──────────────────────────────────────────────────────────────────

generate_summary() {
  local ts
  ts="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  local count
  count="$(ls -d "$RELEASES_DIR"/*/ 2>/dev/null | wc -l)"

  cat > "$SYNC_DIR/SYNC_SUMMARY.txt" <<SUMMARY
Helium Browser — Upstream Sync Summary
=======================================
Date:     $ts
Upstream: ${HELIUM_UPSTREAM_REPO}
Releases: $count

Generated:
  - $RELEASES_DIR/INDEX.md
  - $RELEASES_DIR/CHANGELOG.md
  - Git tags (local)
SUMMARY

  cat "$SYNC_DIR/SYNC_SUMMARY.txt"
}

# ── Main ─────────────────────────────────────────────────────────────────────

log "Starting upstream sync..."

fetch_releases
merge_releases
process_releases
generate_sync_index
generate_changelog
create_git_tags
generate_summary

log "Upstream sync completed."

