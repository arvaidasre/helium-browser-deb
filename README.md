# Helium Browser (Unofficial .deb & .rpm)

This repository provides an easy way to install **Helium Browser** on Linux systems. It automatically tracks the [official upstream releases](https://github.com/imputnet/helium-linux) and builds both `.deb` (Debian/Ubuntu) and `.rpm` (Fedora/RHEL/openSUSE) packages.

## 🚀 Install

### Option 1: Using APT/RPM Repository (Recommended)

#### Debian / Ubuntu

Add the repository and install:

```bash
echo "deb [arch=amd64,arm64 trusted=yes] https://arvaidasre.github.io/helium-browser-deb/apt stable main" | sudo tee /etc/apt/sources.list.d/helium.list
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

*   **GitHub Actions** checks for new upstream releases daily.
*   **FPM** is used to package the upstream tarball into proper Debian and RPM packages.
*   **APT and RPM repositories** are automatically generated and published to [arvaidasre.github.io/helium-browser-deb](https://arvaidasre.github.io/helium-browser-deb) via GitHub Pages.

## 🔗 Upstream Project

This is an unofficial packaging project. The actual browser is developed here:
https://github.com/imputnet/helium-linux
