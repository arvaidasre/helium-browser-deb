#!/usr/bin/env bash
# ==============================================================================
# check-package-arch.sh — Show architecture info from DEB packages
# Usage: ./check-package-arch.sh <deb-file> [deb-file...]
# ==============================================================================
set -euo pipefail

if (( $# == 0 )); then
  echo "Usage: $0 <deb-file> [deb-file...]"
  exit 1
fi

for deb in "$@"; do
  if [[ ! -f "$deb" ]]; then
    echo "Error: File not found: $deb" >&2
    continue
  fi
  echo "=== $(basename "$deb") ==="
  dpkg -I "$deb" | grep -iE 'Architecture|Package|Version'
  echo
done
