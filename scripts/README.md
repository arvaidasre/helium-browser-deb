# Scripts

This folder contains the automation scripts used by CI workflows.

## Common workflows

- **Build & publish:** `./scripts/publish/pipeline.sh`
- **Build only:** `./scripts/build/build.sh`
- **Prerelease build:** `./scripts/build/prerelease.sh`
- **Publish release:** `./scripts/publish/publish.sh`

## Script index

### Build (`scripts/build/`)
| Script | Purpose |
| --- | --- |
| `build.sh` | Build packages and site output. |
| `prerelease.sh` | Build prerelease artifacts. |
| `common.sh` | Shared build helpers used by build scripts (not intended to run directly). |
| `resources/postinst.sh` | Post-install hook for packaging. |

### Publish (`scripts/publish/`)
| Script | Purpose |
| --- | --- |
| `pipeline.sh` | End-to-end build + release + Pages publish. |
| `publish.sh` | Push GitHub release assets + Pages output. |

### Repo (`scripts/repo/`)
| Script | Purpose |
| --- | --- |
| `apt.sh` | Produce APT repository metadata. |
| `rpm.sh` | Produce RPM repository metadata. |

### Upstream (`scripts/upstream/`)
| Script | Purpose |
| --- | --- |
| `check.sh` | Detect upstream Helium Browser releases. |
| `sync.sh` | Pull upstream release metadata. |
| `full_sync.sh` | Sync upstream metadata and rebuild. |

### Utils (`scripts/utils/`)
| Script | Purpose |
| --- | --- |
| `debug.sh` | Local debug helpers for CI tasks. |
| `validate.sh` | Sanity checks for generated repos. |

### Setup (`scripts/setup/`)
| Script | Purpose |
| --- | --- |
| `dev.sh` | Prepare dependencies for build. |
| `install_apt.sh` | Install local APT repo for testing. |
