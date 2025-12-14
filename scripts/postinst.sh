#!/bin/sh
set -e

# Fix chrome-sandbox permissions
if [ -f "/opt/helium/chrome-sandbox" ]; then
    chown root:root "/opt/helium/chrome-sandbox"
    chmod 4755 "/opt/helium/chrome-sandbox"
fi

# Update desktop database if available
if command -v update-desktop-database >/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
