# Helium Browser (DEB)

This repository automatically builds a **Helium** `.deb` package and publishes it to GitHub Releases.

Upstream project: https://github.com/imputnet/helium-linux

## How it works

- GitHub Actions periodically checks the latest `imputnet/helium-linux` Release.
- If this repo does not yet have a Release with the same tag, it creates a small “online installer” `.deb`.
  During install/upgrade, the package downloads the official upstream Linux tarball and installs it into `/opt/helium`.
- It creates a Release with the same tag and uploads:
  - `helium-browser_<version>_<arch>.deb`
  - `SHA256SUMS`

## Install

### Option A: Download from GitHub Releases

Download the `.deb` from this repo’s Releases page and install:

```bash
sudo apt-get update
sudo apt-get install -y ./helium-browser_<version>_<arch>.deb
```

### Option B: APT repository (for automatic updates)

This repo publishes a simple (unsigned) APT repository via GitHub Pages. After you add it, you can upgrade with `apt`.

Note: GitHub Pages cannot host files larger than 100 MB. The full offline `.deb` is therefore published via GitHub Releases,
while the APT repository provides a small installer package which downloads the official upstream Linux tarball during install/upgrade.

1) Enable GitHub Pages for this repo:
   - Settings → Pages
   - Source: `Deploy from a branch`
   - Branch: `gh-pages` (root)

2) Add the APT source (replace `<OWNER>` and `<REPO>`):

```bash
echo "deb [trusted=yes] https://<OWNER>.github.io/<REPO>/ stable main" | sudo tee /etc/apt/sources.list.d/helium-browser.list
sudo apt-get update
sudo apt-get install -y helium-browser
```

Upgrade later:

```bash
sudo apt-get update
sudo apt-get upgrade
```

## Local build (Ubuntu/Debian)

Requirements:

```bash
sudo apt-get update
sudo apt-get install -y jq fakeroot dpkg-dev curl
```

Build from the latest upstream Release:

```bash
./scripts/build_latest_upstream_release.sh --outdir ./dist --package helium-browser
```

## Notes

- The package installs application payload into `/opt/helium` and starts it via `/usr/bin/helium` wrapper.
- This DEB is an online installer: it downloads the upstream build during install/upgrade.
- DEB version is normalized (e.g. `v1.2.3` → `1.2.3`).
