# Scripts

This folder contains the automation scripts used by CI workflows.

All scripts source `lib/common.sh` — the central shared library that provides
logging, dependency checking, architecture mapping, and GitHub API helpers.

## Common workflows

- **Build & publish:** `./scripts/publish/pipeline.sh`
- **Build only:** `./scripts/build/build.sh`
- **Prerelease build:** `./scripts/build/prerelease.sh`
- **Publish release:** `./scripts/publish/publish.sh`

## Script index

### Shared Library (`scripts/lib/`)
| Script | Purpose |
| --- | --- |
| `common.sh` | Constants, logging, `check_deps`, `github_api_get`, arch helpers (sourced, not run). |

### Build (`scripts/build/`)
| Script | Purpose |
| --- | --- |
| `build.sh` | Build DEB + RPM packages from upstream tarball. |
| `prerelease.sh` | Build prerelease artifacts. |
| `common.sh` | Build-specific helpers (workspace, packaging, icons). |
| `resources/postinst.sh` | Post-install hook embedded in packages. |

### Publish (`scripts/publish/`)
| Script | Purpose |
| --- | --- |
| `pipeline.sh` | End-to-end build → repo-gen → publish. |
| `publish.sh` | Assemble APT + RPM repos and site output. |

### Repo (`scripts/repo/`)
| Script | Purpose |
| --- | --- |
| `apt.sh` | Generate APT repository metadata. |
| `rpm.sh` | Generate RPM repository metadata. |

### Upstream (`scripts/upstream/`)
| Script | Purpose |
| --- | --- |
| `check.sh` | Show latest upstream release info. |
| `sync.sh` | Fetch and store all upstream release metadata. |
| `full_sync.sh` | sync → build → publish → validate pipeline. |

### Utils (`scripts/utils/`)
| Script | Purpose |
| --- | --- |
| `debug.sh` | Collect system and repo diagnostics. |
| `validate.sh` | Validate APT + RPM repo structure. |
| `check-package-arch.sh` | Inspect DEB package architecture. |

### Setup (`scripts/setup/`)
| Script | Purpose |
| --- | --- |
| `dev.sh` | Bootstrap development dependencies. |
| `install_apt.sh` | Add the Helium APT source list locally. |
