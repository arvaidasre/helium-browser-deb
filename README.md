# Helium Browser (Unofficial .deb)

This repository provides an easy way to install **Helium Browser** on Debian/Ubuntu-based systems. It automatically tracks the [official upstream releases](https://github.com/imputnet/helium-linux) and builds a `.deb` package.

## 🚀 Install

You can download the latest `.deb` file from the [Releases page](../../releases).

1.  Download the `helium-browser_...deb` file.
2.  Install it using `apt`:

    ```bash
    sudo apt-get update
    sudo apt-get install ./helium-browser_*.deb
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
*   **FPM** is used to package the AppImage into a proper Debian package.

## 🔗 Upstream Project

This is an unofficial packaging project. The actual browser is developed here:
https://github.com/imputnet/helium-linux
