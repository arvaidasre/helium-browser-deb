# Packaging notes

Šiame repozitorijoje `.deb` paketas surenkamas skriptais iš `scripts/` (naudojant `dpkg-deb`).

Paketavimo schema:

- Programos payload → `/opt/helium` (iš upstream AppImage `squashfs-root`)
- Wrapper → `/usr/bin/helium` (kviečia `/opt/helium/AppRun`)
- Desktop entry → `/usr/share/applications/helium.desktop`
- Icon (best-effort) → `/usr/share/icons/hicolor/512x512/apps/helium.png`
