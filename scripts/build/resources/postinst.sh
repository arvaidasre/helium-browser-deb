#!/bin/sh
set -e

# Reload AppArmor profile
if command -v apparmor_parser >/dev/null 2>&1; then
    if [ -f "/etc/apparmor.d/opt.helium.helium" ]; then
        apparmor_parser -r -T -W /etc/apparmor.d/opt.helium.helium 2>/dev/null || true
    fi
fi

# Update desktop database if available
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi

# Update icon cache if available
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Update mime database if available
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime 2>/dev/null || true
fi
