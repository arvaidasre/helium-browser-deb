# Helium Browser (Unofficial .deb)

This repository provides an easy way to install and update **Helium Browser** on Debian/Ubuntu-based systems. It automatically tracks the [official upstream releases](https://github.com/imputnet/helium-linux) and builds `.deb` packages.

## 🚀 Quick Install

The easiest way to install Helium Browser and enable automatic updates is to run the following command:

```bash
curl -sSL https://arvaidasre.github.io/helium-browser-deb/setup.sh | sudo bash
```

This script will:
1.  Add the repository to your system.
2.  Install Helium Browser.

## 📦 Other Installation Methods

### Manual APT Repository Setup

If you prefer to set it up manually:

1.  Add the repository source:
    ```bash
    echo "deb [trusted=yes] https://arvaidasre.github.io/helium-browser-deb/ stable main" | sudo tee /etc/apt/sources.list.d/helium-browser.list
    ```

2.  Update and install:
    ```bash
    sudo apt-get update
    sudo apt-get install helium-browser
    ```

### Download .deb Manually

You can also download the standalone `.deb` file from the [Releases page](../../releases).

*   **Online Installer (`helium-browser-online_...deb`)**: Smaller file. Downloads the latest browser version during installation. Recommended for fast internet connections.
*   **Offline Installer (`helium-browser_...deb`)**: Larger file. Contains the full browser. Good for offline installation.

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
*   **FPM** is used to package the AppImage into a proper Debian package.
*   **APT Repository** is hosted on GitHub Pages for easy updates via `apt upgrade`.

## 🔗 Upstream Project

This is an unofficial packaging project. The actual browser is developed here:
https://github.com/imputnet/helium-linux
