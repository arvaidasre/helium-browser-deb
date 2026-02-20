# Scripts

This folder contains the automation scripts used by CI workflows.

All scripts source `lib/common.sh` — the central shared library that provides
logging, dependency checking, architecture mapping, and GitHub API helpers.

## 🆕 Version 2 (Recommended)

See [README-v2.md](README-v2.md) for the new signed package building system.

**Quick start with v2:**
```bash
# Setup GPG
./scripts/utils/gpg-setup.sh generate

# Build signed packages
CHANNEL=stable ./scripts/build/build-v2.sh

# Generate signed repos
./scripts/repo/apt-v2.sh
./scripts/repo/rpm-v2.sh
```

## Common workflows

- **Build & publish:** `./scripts/publish/pipeline.sh`
- **Build only:** `./scripts/build/build.sh`
- **Build v2 (signed):** `./scripts/build/build-v2.sh`
- **Prerelease build:** `./scripts/build/prerelease.sh`
- **Publish release:** `./scripts/publish/publish.sh`

## Script index

### Shared Library (`scripts/lib/`)
| Script | Purpose |
| --- | --- |
| `common.sh` | Constants, logging, `check_deps`, `github_api_get`, arch helpers (sourced, not run). |
| `deps-map.sh` | **NEW:** Distribution-specific dependency mappings for DEB/RPM. |

### Build (`scripts/build/`)
| Script | Purpose |
| --- | --- |
| `build.sh` | Build DEB + RPM packages from upstream tarball. |
| `build-v2.sh` | **NEW:** Build with GPG signing, checksum verification, multi-channel support. |
| `build-all.sh` | **NEW:** Build both stable and nightly channels. |
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
| `apt-v2.sh` | **NEW:** Generate signed APT repository with InRelease/Release.gpg. |
| `rpm.sh` | Generate RPM repository metadata. |
| `rpm-v2.sh` | **NEW:** Generate signed RPM repository with repomd.xml.asc. |

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
| `gpg-setup.sh` | **NEW:** GPG key generation, import, export for package signing. |
| `checksum-verify.sh` | **NEW:** Verify upstream tarball checksums. |

### Setup (`scripts/setup/`)
| Script | Purpose |
| --- | --- |
| `dev.sh` | Bootstrap development dependencies. |
| `install_apt.sh` | Add the Helium APT source list locally. |
