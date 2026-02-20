#!/usr/bin/env bash
# ==============================================================================
# Multi-channel build wrapper
# ==============================================================================
# Builds both stable and nightly channels
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building STABLE channel..."
CHANNEL=stable "$SCRIPT_DIR/build-v2.sh"

echo ""
echo "Building NIGHTLY channel..."
CHANNEL=nightly "$SCRIPT_DIR/build-v2.sh"
