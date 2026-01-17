#!/bin/sh
set -e

# Reload AppArmor profile
if command -v apparmor_parser >/dev/null; then
    if [ -f "/etc/apparmor.d/opt.helium.helium" ]; then
        apparmor_parser -r -T -W /etc/apparmor.d/opt.helium.helium || true
    fi
fi

# Update desktop database if available
if command -v update-desktop-database >/dev/null; then
    update-desktop-database /usr/share/applications || true
fi
