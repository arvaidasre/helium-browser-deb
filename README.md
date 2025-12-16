# Helium Browser Repository

[![Build Status](https://github.com/arvaidasre/helium-browser-deb/workflows/Build%20DEB%20and%20RPM%20from%20upstream%20Tarball/badge.svg)](https://github.com/arvaidasre/helium-browser-deb/actions)
[![Update Repos](https://github.com/arvaidasre/helium-browser-deb/workflows/Update%20APT%20and%20RPM%20Repositories/badge.svg)](https://github.com/arvaidasre/helium-browser-deb/actions)

This repository provides automated packages of [Helium Browser](https://github.com/imputnet/helium-linux) for Linux distributions.

## 🚀 Quick Install

### Debian / Ubuntu / Linux Mint
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
```

### Fedora / RHEL / CentOS / Rocky Linux
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
```

## 📦 Manual Installation

### APT (Debian/Ubuntu)

**Option 1: Using our install script (Recommended)**
```bash
curl -fsSL https://raw.githubusercontent.com/arvaidasre/helium-browser-deb/main/scripts/install-apt-repo.sh | sudo bash
sudo apt-get update
sudo apt-get install helium-browser
```

**Option 2: Manual repository setup**
```bash
CODENAME="$(. /etc/os-release && echo ${VERSION_CODENAME:-stable})"
echo "deb [arch=amd64,arm64] https://arvaidasre.github.io/helium-browser-deb/apt $CODENAME main" | sudo tee /etc/apt/sources.list.d/helium-browser.list
sudo apt-get update
sudo apt-get install helium-browser
```

#### Fedora / RHEL / openSUSE

Create a repository file:

```bash
sudo tee /etc/yum.repos.d/helium.repo <<EOF
[helium]
name=Helium Browser Repository
baseurl=https://arvaidasre.github.io/helium-browser-deb/rpm/\$basearch
enabled=1
gpgcheck=0
EOF

sudo dnf install helium-browser
# or for openSUSE:
# sudo zypper install helium-browser
```

### Option 2: Direct Download

You can also download the latest packages directly from the [Releases page](../../releases).

#### Debian / Ubuntu
1.  Download the `helium-browser_...deb` file.
2.  Install it using `apt`:
    ```bash
    sudo apt-get update
    sudo apt-get install ./helium-browser_*.deb
    ```

#### Fedora / RHEL / openSUSE
1.  Download the `helium-browser-...rpm` file.
2.  Install it using `dnf` or `zypper`:
    ```bash
    sudo dnf install ./helium-browser-*.rpm
    # or
    sudo zypper install ./helium-browser-*.rpm
    ```

## 🛠️ Building Locally

If you want to build the package yourself:

1.  **Install dependencies:**
    ```bash
    sudo apt-get update
    sudo apt-get install -y curl jq ruby ruby-dev build-essential
    sudo gem install fpm
    ```

2.  **Run the build script:**
    ```bash
    ./scripts/build.sh
    ```
    The artifacts will be created in the `dist/` directory.

## ℹ️ How it Works

*   **GitHub Actions** checks for new upstream releases daily at 3:00 AM UTC.
*   **FPM** is used to package the upstream tarball into proper Debian and RPM packages.
*   **APT and RPM repositories** are automatically generated and published to [arvaidasre.github.io/helium-browser-deb](https://arvaidasre.github.io/helium-browser-deb) via GitHub Pages.
*   **Repositories are automatically updated daily** at 4:00 AM UTC to ensure the latest packages are available.

## 🔗 Upstream Project

This is an unofficial packaging project. The actual browser is developed here:
https://github.com/imputnet/helium-linux
