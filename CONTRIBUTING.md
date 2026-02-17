# Contributing to Helium Browser Linux Repository

Thank you for your interest in contributing! This document provides guidelines
for setting up a development environment and submitting changes.

## Prerequisites

- **Linux** (Debian/Ubuntu or Fedora/RHEL)
- `bash` ≥ 4.0, `curl`, `jq`, `git`
- `dpkg-dev` and `createrepo_c` (for repository generation)
- `fpm` (for package building) — install via `gem install fpm`

Run the automated setup script to install everything:

```bash
./scripts/setup/dev.sh
```

## Repository structure

| Directory        | Purpose                                    |
|------------------|--------------------------------------------|
| `scripts/lib/`   | Shared shell library (`common.sh`)         |
| `scripts/build/`  | Package build scripts                     |
| `scripts/publish/` | Release publication pipeline             |
| `scripts/repo/`   | APT / RPM repository generation           |
| `scripts/upstream/` | Upstream release sync                   |
| `scripts/utils/`  | Debugging and validation utilities         |
| `scripts/setup/`  | Developer environment setup               |
| `site/`           | GitHub Pages content & install scripts    |
| `.github/workflows/` | CI/CD automation                       |

See [docs/REPO_LAYOUT.md](docs/REPO_LAYOUT.md) for the full layout reference.

## Shell coding conventions

1. **Shebang** — always `#!/usr/bin/env bash`.
2. **Strict mode** — every script must begin with `set -euo pipefail`.
3. **Shared library** — source `scripts/lib/common.sh` instead of redefining
   helpers like `log`, `err`, `check_deps`, etc.
4. **Constants** — use `readonly` for values that never change.
5. **Quoting** — always quote variables: `"$var"`, not `$var`.
6. **Linting** — run `shellcheck scripts/**/*.sh` before committing.

## Submitting changes

1. Fork the repository and create a feature branch.
2. Make your changes with clear, descriptive commit messages.
3. Run `shellcheck scripts/**/*.sh` to catch common issues.
4. Open a Pull Request with a summary of what changed and why.

## Automation overview

| Workflow            | Trigger           | Purpose                          |
|---------------------|-------------------|----------------------------------|
| `watch-upstream`    | Every 15 min      | Detect new upstream releases     |
| `auto-build`        | Hourly / dispatch | Build, release, deploy to Pages  |
| `healthcheck`       | Hourly            | Monitor repo endpoints           |
| `cleanup`           | Weekly (Sunday)   | Remove old releases (keep 5)     |
| `rebuild-release`   | Manual            | Rebuild any version on-demand    |
| `test-apt-repo`     | Manual            | Validate APT repo generation     |
