# <img src="https://avatars.githubusercontent.com/u/234597297?v=4" width="32" height="32"> Helium Browser Linux Repository

<p align="center">
  <img src="https://img.shields.io/badge/Status-Fully_Automated-success?style=for-the-badge&logo=github-actions&logoColor=white" alt="Status">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Platform-Linux-lightgrey?style=for-the-badge&logo=linux&logoColor=white" alt="Platform">
</p>

<p align="center">
  <b>Automated Packaging & Repository for Helium Browser</b>
  <br>
  <i>Fast, secure, and privacy-focused browsing for Linux.</i>
</p>

---

This repository provides automated, up-to-date packages of [Helium Browser](https://github.com/imputnet/helium-linux).

## Quick Install

**Debian / Ubuntu / Mint:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
```

**Fedora / RHEL / CentOS:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
```

## Manual Setup

Visit our **[Web Page](https://arvaidasre.github.io/helium-browser-deb/)** for detailed instructions or download files from [Releases](../../releases).

## Repository Layout

- `scripts/lib/`: shared shell library (sourced by all scripts)
- `scripts/`: build, publish, upstream-sync, and utility scripts
- `site/`: public web assets and one-liner install scripts
- `site/public/`: generated APT/RPM repo + Pages artifacts (CI-only)
- `docs/`: contributor-facing documentation

## Repository Organization

If you are contributing or maintaining the automation, start here:

- [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) for a full layout overview
- [`scripts/README.md`](scripts/README.md) for script descriptions
- [`site/README.md`](site/README.md) for Pages content notes

---

## Automation System

This repository is **fully automated**. No manual intervention required.

### How It Works

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| **Watch Upstream** | Every 15 minutes | Detects new upstream releases and triggers build |
| **Auto Build** | Every hour | Backup check + builds packages, creates GitHub release, deploys to Pages |
| **Healthcheck** | Every hour | Monitors repository endpoints, triggers rebuild if broken |
| **Cleanup** | Weekly (Sunday) | Removes old releases, keeps last 5 stable |

## Project Info

| System | Status |
| :--- | :--- |
| **Auto Build** | [![Build](https://github.com/arvaidasre/helium-browser-deb/actions/workflows/auto-build.yml/badge.svg)](https://github.com/arvaidasre/helium-browser-deb/actions/workflows/auto-build.yml) |
| **Healthcheck** | [![Health](https://github.com/arvaidasre/helium-browser-deb/actions/workflows/healthcheck.yml/badge.svg)](https://github.com/arvaidasre/helium-browser-deb/actions/workflows/healthcheck.yml) |

- **Repository**: [arvaidasre/helium-browser-deb](https://github.com/arvaidasre/helium-browser-deb)
- **Automation**: ![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white)
- **Upstream**: [imputnet/helium-linux](https://github.com/imputnet/helium-linux)

---

&copy; 2025–2026 Arvaidas Rekis. Licensed under [MIT](LICENSE).
