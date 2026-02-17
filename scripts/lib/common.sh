#!/usr/bin/env bash
# shellcheck disable=SC2034
# ==============================================================================
# Helium Browser Packaging — Shared Library
# ==============================================================================
# Sourced by all scripts. Provides logging, dependency checks, architecture
# helpers, GitHub API utilities, and common constants.
#
# Usage:  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# ==============================================================================

set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────

readonly HELIUM_PACKAGE_NAME="helium-browser"
readonly HELIUM_UPSTREAM_REPO="imputnet/helium-linux"
readonly HELIUM_UPSTREAM_URL="https://github.com/${HELIUM_UPSTREAM_REPO}"
readonly HELIUM_REPO_URL="https://arvaidasre.github.io/helium-browser-deb"
readonly HELIUM_GITHUB_REPO="arvaidasre/helium-browser-deb"

# Resolved once; available to all scripts that source this file.
HELIUM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELIUM_PROJECT_ROOT="$(cd "${HELIUM_LIB_DIR}/../.." && pwd)"

# ─── Terminal colours ─────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    readonly _CLR_RESET='\033[0m'
    readonly _CLR_BOLD='\033[1m'
    readonly _CLR_RED='\033[1;31m'
    readonly _CLR_GREEN='\033[1;32m'
    readonly _CLR_YELLOW='\033[1;33m'
    readonly _CLR_BLUE='\033[1;34m'
    readonly _CLR_CYAN='\033[1;36m'
else
    readonly _CLR_RESET='' _CLR_BOLD='' _CLR_RED='' _CLR_GREEN=''
    readonly _CLR_YELLOW='' _CLR_BLUE='' _CLR_CYAN=''
fi

# ─── Logging ──────────────────────────────────────────────────────────────────

# Override LOG_PREFIX in each script before sourcing, e.g.:
#   LOG_PREFIX="BUILD"
: "${LOG_PREFIX:=HELIUM}"

log()     { echo -e "${_CLR_BLUE}[${LOG_PREFIX}]${_CLR_RESET} $*"; }
warn()    { echo -e "${_CLR_YELLOW}[WARN]${_CLR_RESET} $*"; }
err()     { echo -e "${_CLR_RED}[ERROR]${_CLR_RESET} $*" >&2; exit 1; }
section() { echo -e "\n${_CLR_CYAN}=== $* ===${_CLR_RESET}"; }

# ─── Dependency checking ─────────────────────────────────────────────────────

# check_deps CMD [CMD ...]
#   Exits with an error if any required command is missing.
check_deps() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} )); then
        err "Missing dependencies: ${missing[*]}"
    fi
}

# check_deps_warn CMD [CMD ...]
#   Prints a warning for each missing command but does not exit.
check_deps_warn() {
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "Missing optional dependency: $cmd"
        fi
    done
}

# ─── File / size helpers ─────────────────────────────────────────────────────

# Cross-platform file size (Linux stat -c%s, macOS stat -f%z).
file_size() {
    local f="$1"
    stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0
}

# Cross-platform file mtime.
file_mtime() {
    local f="$1"
    if stat -c '%y' "$f" >/dev/null 2>&1; then
        stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1-2
    else
        stat -f '%Sm' "$f" 2>/dev/null || echo "unknown"
    fi
}

# ─── Architecture helpers ────────────────────────────────────────────────────

# Populates: ARCH, DEB_ARCH, RPM_ARCH, ASSET_PATTERN
# Honours ARCH_OVERRIDE environment variable.
set_arch_vars() {
    local raw="${ARCH_OVERRIDE:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"

    case "$raw" in
        x86_64)  raw="amd64"  ;;
        aarch64) raw="arm64"  ;;
    esac

    case "$raw" in
        amd64)
            ASSET_PATTERN="x86_64|amd64"
            DEB_ARCH="amd64"
            RPM_ARCH="x86_64"
            ;;
        arm64)
            ASSET_PATTERN="arm64|aarch64"
            DEB_ARCH="arm64"
            RPM_ARCH="aarch64"
            ;;
        *)
            ASSET_PATTERN="$raw"
            DEB_ARCH="$raw"
            RPM_ARCH="$raw"
            ;;
    esac

    ARCH="$raw"
}

# ─── Version helpers ─────────────────────────────────────────────────────────

# Strips leading 'v', spaces, and converts underscores to dots.
normalize_version() {
    local v="$1"
    v="${v#v}"
    v="${v// /}"
    v="${v//_/.}"
    echo "$v"
}

# ─── GitHub API helpers ───────────────────────────────────────────────────────

# Authenticated (if GITHUB_TOKEN set) JSON fetch.
github_api_get() {
    local url="$1"
    local -a headers=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl -fsSL "${headers[@]}" "$url"
}

# Human-readable list of asset names from release JSON.
get_assets_summary() {
    jq -r '(.assets // []) | map(.name) | if length == 0 then "(none)" else join("\n") end' <<<"$1"
}

# ─── Release JSON helpers ────────────────────────────────────────────────────

validate_release_json() {
    local json="$1"
    local tag_name asset_count

    tag_name="$(jq -r '.tag_name // empty' <<<"$json")"
    if [[ -z "$tag_name" || "$tag_name" == "null" ]]; then
        err "Upstream release response is missing tag_name."
    fi

    asset_count="$(jq -r '(.assets // []) | length' <<<"$json")"
    if [[ "$asset_count" == "0" ]]; then
        err "Upstream release $tag_name has no assets.\\nAvailable: $(get_assets_summary "$json")"
    fi
}

# Resolve the first Linux tarball URL from release JSON.
resolve_tarball_url() {
    local json="$1"
    local url=""

    # 1. Try matching arch-specific Linux tarball
    url="$(jq -r --arg pat "$ASSET_PATTERN" '(.assets // [])[]
        | select(.name | test("linux"; "i"))
        | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
        | select(.name | test($pat; "i"))
        | .browser_download_url' <<<"$json" | head -n 1)"

    # 2. Fallback: any Linux tarball
    if [[ -z "$url" ]]; then
        url="$(jq -r '(.assets // [])[]
            | select(.name | test("linux"; "i"))
            | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
            | .browser_download_url' <<<"$json" | head -n 1)"
    fi

    # 3. Fallback: any tarball
    if [[ -z "$url" ]]; then
        url="$(jq -r '(.assets // [])[]
            | select(.name | test("\\.tar\\.(xz|gz|zst|bz2)$"; "i"))
            | .browser_download_url' <<<"$json" | head -n 1)"
    fi

    echo "$url"
}

# ─── APT / Packages validation ───────────────────────────────────────────────

validate_packages_file() {
    local file="$1"
    [[ -s "$file" ]] || err "Packages file is empty: $file"
    grep -q '^Package:' "$file" || err "Packages file has no Package headers: $file"

    awk -v RS='' '
        $0 !~ /^Package:/ { bad++ }
        END { if (bad > 0) exit 1 }
    ' "$file" || err "Packages file contains invalid stanza(s): $file"
}

# ─── RPM metadata validation ─────────────────────────────────────────────────

validate_rpm_metadata() {
    local dir="$1"
    local repodata="$dir/repodata"

    [[ -d "$repodata" ]]              || err "Missing RPM repodata: $repodata"
    [[ -s "$repodata/repomd.xml" ]]   || err "Missing repomd.xml: $repodata/repomd.xml"
    grep -q '<repomd' "$repodata/repomd.xml" || err "Invalid repomd.xml: $repodata/repomd.xml"

    if ! compgen -G "$repodata/*primary*.*" >/dev/null &&
       ! compgen -G "$repodata/*filelists*.*" >/dev/null &&
       ! compgen -G "$repodata/*other*.*" >/dev/null; then
        err "RPM metadata missing core files in $repodata"
    fi
}
