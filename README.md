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

<p align="center">
  <i>Click on your language to see instructions / Pasirinkite kalba instrukcijoms / Выберите язык для инструкций</i>
</p>

---

<details>
<summary><b>English - Click to expand</b></summary>
<br>

This repository provides automated, up-to-date packages of [Helium Browser](https://github.com/imputnet/helium-linux).

### <img src="https://img.shields.io/badge/Quick_Install-2563eb?style=flat-square&logo=rocket&logoColor=white" height="24">

**![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white) ![Debian](https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white) ![Mint](https://img.shields.io/badge/Linux_Mint-27AE60?style=flat-square&logo=linux-mint&logoColor=white) Debian / Ubuntu / Mint:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
```

**![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=flat-square&logo=fedora&logoColor=white) ![RedHat](https://img.shields.io/badge/RHEL-CC0000?style=flat-square&logo=red-hat&logoColor=white) Fedora / RHEL / CentOS:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
```

### <img src="https://img.shields.io/badge/Manual_Setup-6b7280?style=flat-square&logo=gear&logoColor=white" height="24">
Visit our **[Web Page](https://arvaidasre.github.io/helium-browser-deb/)** for detailed instructions or download files from [Releases](../../releases).

### Repository Layout

- `scripts/`: build + publish scripts
- `site/`: public web assets and install scripts
- `site/public/`: generated APT/RPM repo + Pages artifacts (generated in CI)
- `docs/`: contributor-facing documentation

### Repository Organization

If you are contributing or maintaining the automation, start here:

- [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) for a full layout overview
- [`scripts/README.md`](scripts/README.md) for script descriptions
- [`site/README.md`](site/README.md) for Pages content notes

</details>

---

<details>
<summary><b>Lietuviu - Iskleisti instrukcijas</b></summary>
<br>

Si repozitorija pateikia automatiskai paruostus [Helium Browser](https://github.com/imputnet/helium-linux) paketus.

### <img src="https://img.shields.io/badge/Greitas_Diegimas-2563eb?style=flat-square&logo=rocket&logoColor=white" height="24">

**Debian / Ubuntu / Mint:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
```

**Fedora / RHEL / CentOS:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
```

### <img src="https://img.shields.io/badge/Rankinis_Nustatymas-6b7280?style=flat-square&logo=gear&logoColor=white" height="24">
Apsilankykite **[interneto svetaineje](https://arvaidasre.github.io/helium-browser-deb/)** arba atsisiuskite failus is [Releases skilties](../../releases).

### Repo struktura

- `scripts/`: build + publish skriptai
- `site/`: public assets ir install skriptai
- `site/public/`: generuojamas APT/RPM repo (CI)
- `docs/`: dokumentacija prisidedantiems

### Repo organizavimas

- [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) apraso pilna struktura
- [`scripts/README.md`](scripts/README.md) skriptu aprasai
- [`site/README.md`](site/README.md) Pages turinys

</details>

---

<details>
<summary><b>Русский - Показать инструкции</b></summary>
<br>

Этот репозиторий предоставляет актуальные пакеты [Helium Browser](https://github.com/imputnet/helium-linux).

### <img src="https://img.shields.io/badge/Быстрая_Установка-2563eb?style=flat-square&logo=rocket&logoColor=white" height="24">

**Debian / Ubuntu / Mint:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install.sh | bash
```

**Fedora / RHEL / CentOS:**
```bash
curl -fsSL https://arvaidasre.github.io/helium-browser-deb/install-rpm.sh | bash
```

### <img src="https://img.shields.io/badge/Ручная_Настройка-6b7280?style=flat-square&logo=gear&logoColor=white" height="24">
Посетите нашу **[веб-страницу](https://arvaidasre.github.io/helium-browser-deb/)** или скачайте файлы из [раздела релизов](../../releases).

### Структура репозитория

- `scripts/`: scripts for build + publish
- `site/`: public assets and install scripts
- `site/public/`: generated APT/RPM repo (CI)
- `docs/`: contributor documentation

### Организация репозитория

- [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) — обзор структуры
- [`scripts/README.md`](scripts/README.md) — описание скриптов
- [`site/README.md`](site/README.md) — заметки по Pages

</details>

---

## Automation System

This repository is **fully automated**. No manual intervention required.

### How It Works

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| **Watch Upstream** | Every 5 minutes | Detects new upstream releases immediately and triggers build |
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

&copy; 2025 Arvaidas Rekis.
