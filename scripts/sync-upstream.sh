#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
UPSTREAM_REPO="imputnet/helium-linux"
UPSTREAM_URL="https://github.com/$UPSTREAM_REPO"
GITHUB_API="https://api.github.com/repos/$UPSTREAM_REPO"
SYNC_DIR="${SYNC_DIR:-sync}"
RELEASES_DIR="${RELEASES_DIR:-releases}"

# --- Helper Functions ---
log() { echo -e "\033[1;34m[SYNC]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

check_deps() {
  local deps=(curl jq git)
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "Missing dependency: $cmd"
    fi
  done
}

fetch_releases() {
  log "Fetching releases from $UPSTREAM_REPO..."
  
  mkdir -p "$SYNC_DIR"
  
  local page=1
  local per_page=100
  local total_releases=0
  
  while true; do
    log "Fetching page $page..."
    
    local url="$GITHUB_API/releases?page=$page&per_page=$per_page"
    local response
    
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      response=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url")
    else
      response=$(curl -fsSL "$url")
    fi
    
    # Check if response is empty array
    if [[ "$response" == "[]" ]]; then
      break
    fi
    
    # Save page to file
    echo "$response" > "$SYNC_DIR/releases_page_${page}.json"
    
    local count=$(echo "$response" | jq 'length')
    total_releases=$((total_releases + count))
    
    log "Page $page: $count releases"
    
    if [[ $count -lt $per_page ]]; then
      break
    fi
    
    ((page++))
  done
  
  log "Total releases fetched: $total_releases"
}

merge_releases() {
  log "Merging releases into single file..."
  
  local merged_file="$SYNC_DIR/all_releases.json"
  
  # Combine all pages into single array
  jq -s 'add' "$SYNC_DIR"/releases_page_*.json > "$merged_file"
  
  log "Merged releases: $merged_file"
}

process_releases() {
  log "Processing releases..."
  
  mkdir -p "$RELEASES_DIR"
  
  local merged_file="$SYNC_DIR/all_releases.json"
  local release_count=$(jq 'length' "$merged_file")
  
  log "Processing $release_count releases..."
  
  for i in $(seq 0 $((release_count - 1))); do
    local release=$(jq ".[$i]" "$merged_file")
    local tag=$(echo "$release" | jq -r '.tag_name')
    local name=$(echo "$release" | jq -r '.name // .tag_name')
    local body=$(echo "$release" | jq -r '.body // ""')
    local created_at=$(echo "$release" | jq -r '.created_at')
    local published_at=$(echo "$release" | jq -r '.published_at')
    local prerelease=$(echo "$release" | jq -r '.prerelease')
    local draft=$(echo "$release" | jq -r '.draft')
    local author=$(echo "$release" | jq -r '.author.login')
    local asset_count=$(echo "$release" | jq '.assets | length')
    
    # Create release directory
    local release_dir="$RELEASES_DIR/$tag"
    mkdir -p "$release_dir"
    
    # Save release metadata
    cat > "$release_dir/metadata.json" <<EOF
{
  "tag": "$tag",
  "name": "$name",
  "author": "$author",
  "created_at": "$created_at",
  "published_at": "$published_at",
  "prerelease": $prerelease,
  "draft": $draft,
  "asset_count": $asset_count,
  "upstream_url": "$UPSTREAM_URL/releases/tag/$tag"
}
EOF
    
    # Save release notes
    echo "$body" > "$release_dir/RELEASE_NOTES.md"
    
    # Save assets list
    echo "$release" | jq '.assets[] | {name, size, download_count, browser_download_url}' > "$release_dir/assets.json"
    
    log "Processed: $tag (author: $author, assets: $asset_count)"
  done
}

generate_sync_index() {
  log "Generating sync index..."
  
  local index_file="$RELEASES_DIR/INDEX.md"
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  
  cat > "$index_file" <<EOF
# Helium Browser Releases - Upstream Sync

**Last synced:** $timestamp
**Upstream:** [$UPSTREAM_REPO]($UPSTREAM_URL)

## Release Summary

EOF
  
  # Add release summary table
  echo "| Tag | Name | Author | Type | Assets | Date |" >> "$index_file"
  echo "|-----|------|--------|------|--------|------|" >> "$index_file"
  
  for release_dir in "$RELEASES_DIR"/*/; do
    [[ -d "$release_dir" ]] || continue
    [[ -f "$release_dir/metadata.json" ]] || continue
    
    local meta=$(cat "$release_dir/metadata.json")
    local tag=$(echo "$meta" | jq -r '.tag')
    local name=$(echo "$meta" | jq -r '.name')
    local author=$(echo "$meta" | jq -r '.author')
    local prerelease=$(echo "$meta" | jq -r '.prerelease')
    local asset_count=$(echo "$meta" | jq -r '.asset_count')
    local published_at=$(echo "$meta" | jq -r '.published_at' | cut -d'T' -f1)
    
    local type="Release"
    [[ "$prerelease" == "true" ]] && type="Pre-release"
    
    echo "| [$tag]($UPSTREAM_URL/releases/tag/$tag) | $name | $author | $type | $asset_count | $published_at |" >> "$index_file"
  done
  
  log "Index generated: $index_file"
}

generate_changelog() {
  log "Generating combined changelog..."
  
  local changelog_file="$RELEASES_DIR/CHANGELOG.md"
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  
  cat > "$changelog_file" <<EOF
# Helium Browser - Complete Changelog

**Synced from:** [$UPSTREAM_REPO]($UPSTREAM_URL)
**Last update:** $timestamp

---

EOF
  
  # Add releases in reverse chronological order
  for release_dir in $(ls -d "$RELEASES_DIR"/*/ | sort -r); do
    [[ -d "$release_dir" ]] || continue
    [[ -f "$release_dir/metadata.json" ]] || continue
    
    local meta=$(cat "$release_dir/metadata.json")
    local tag=$(echo "$meta" | jq -r '.tag')
    local name=$(echo "$meta" | jq -r '.name')
    local author=$(echo "$meta" | jq -r '.author')
    local published_at=$(echo "$meta" | jq -r '.published_at')
    local prerelease=$(echo "$meta" | jq -r '.prerelease')
    local upstream_url=$(echo "$meta" | jq -r '.upstream_url')
    
    local type=""
    [[ "$prerelease" == "true" ]] && type=" (Pre-release)"
    
    cat >> "$changelog_file" <<EOF
## [$tag]($upstream_url)$type

**Author:** $author  
**Published:** $published_at

EOF
    
    # Add release notes
    if [[ -f "$release_dir/RELEASE_NOTES.md" ]]; then
      cat "$release_dir/RELEASE_NOTES.md" >> "$changelog_file"
    fi
    
    echo "" >> "$changelog_file"
    echo "---" >> "$changelog_file"
    echo "" >> "$changelog_file"
  done
  
  log "Changelog generated: $changelog_file"
}

create_git_tags() {
  log "Creating/updating git tags from upstream releases..."
  
  local created=0
  local updated=0
  local skipped=0
  
  for release_dir in "$RELEASES_DIR"/*/; do
    [[ -d "$release_dir" ]] || continue
    [[ -f "$release_dir/metadata.json" ]] || continue
    
    local meta=$(cat "$release_dir/metadata.json")
    local tag=$(echo "$meta" | jq -r '.tag')
    local name=$(echo "$meta" | jq -r '.name')
    local body=$(cat "$release_dir/RELEASE_NOTES.md" 2>/dev/null || echo "")
    local author=$(echo "$meta" | jq -r '.author')
    local published_at=$(echo "$meta" | jq -r '.published_at')
    
    # Check if tag exists locally
    if git rev-parse "$tag" >/dev/null 2>&1; then
      log "Tag already exists: $tag (skipped)"
      ((skipped++))
      continue
    fi
    
    # Create annotated tag with release info
    local tag_message="$name

Author: $author
Published: $published_at
Upstream: $UPSTREAM_URL/releases/tag/$tag

$body"
    
    git tag -a "$tag" -m "$tag_message" 2>/dev/null || {
      warn "Could not create tag: $tag"
      continue
    }
    
    log "Created tag: $tag"
    ((created++))
  done
  
  log "Tags summary: created=$created, skipped=$skipped"
  
  if [[ $created -gt 0 ]]; then
    log "To push tags to remote, run: git push origin --tags"
  fi
}

generate_summary() {
  log "Generating sync summary..."
  
  local summary_file="$SYNC_DIR/SYNC_SUMMARY.txt"
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  
  cat > "$summary_file" <<EOF
Helium Browser - Upstream Sync Summary
======================================

Sync Date: $timestamp
Upstream: $UPSTREAM_REPO
Upstream URL: $UPSTREAM_URL

Synced Data:
  - Releases directory: $RELEASES_DIR
  - Sync cache: $SYNC_DIR
  - Release count: $(ls -d "$RELEASES_DIR"/*/ 2>/dev/null | wc -l)

Generated Files:
  - INDEX.md: Release summary table
  - CHANGELOG.md: Complete changelog with all release notes
  - Git tags: Local tags created from upstream releases

Next Steps:
  1. Review synced releases: ls -la $RELEASES_DIR/
  2. Check changelog: cat $RELEASES_DIR/CHANGELOG.md
  3. Verify git tags: git tag -l
  4. Push tags: git push origin --tags
  5. Commit sync data: git add $RELEASES_DIR/ && git commit -m "chore: sync upstream releases"

EOF
  
  cat "$summary_file"
}

# --- Main ---

check_deps

log "Starting upstream sync process..."
log "Upstream repository: $UPSTREAM_REPO"

fetch_releases
merge_releases
process_releases
generate_sync_index
generate_changelog
create_git_tags
generate_summary

log "Upstream sync completed successfully!"

