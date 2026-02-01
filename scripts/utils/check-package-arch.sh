#!/usr/bin/env bash
set -e

# Utility to check the actual architecture of DEB packages
# Usage: ./check-package-arch.sh <path-to-deb-file>

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <deb-file> [deb-file...]"
  echo ""
  echo "This script checks the actual architecture from the DEB package's control file"
  exit 1
fi

for deb in "$@"; do
  if [[ ! -f "$deb" ]]; then
    echo "Error: File not found: $deb"
    continue
  fi

  echo "=== $(basename "$deb") ==="
  dpkg -I "$deb" | grep -i Architecture
  dpkg -I "$deb" | grep -i Package
  dpkg -I "$deb" | grep -i Version
  echo ""
done
