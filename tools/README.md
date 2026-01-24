# Tools

This folder contains the automation scripts used by CI workflows.

## Common workflows

- **Build & publish:** `./tools/build-and-publish.sh`
- **Build only:** `./tools/build.sh`
- **Prerelease build:** `./tools/build-prerelease.sh`
- **Publish release:** `./tools/publish-release.sh`

## Script index

| Script | Purpose |
| --- | --- |
| `build-and-publish.sh` | End-to-end build + release + Pages publish. |
| `build-common.sh` | Shared build helpers used by build scripts (not intended to run directly). |
| `build-prerelease.sh` | Build prerelease artifacts. |
| `build.sh` | Build packages and site output. |
| `check-upstream.sh` | Detect upstream Helium Browser releases. |
| `debug.sh` | Local debug helpers for CI tasks. |
| `full-sync-and-build.sh` | Sync upstream metadata and rebuild. |
| `generate-apt-repo.sh` | Produce APT repository metadata. |
| `generate-rpm-repo.sh` | Produce RPM repository metadata. |
| `install-apt-repo.sh` | Install local APT repo for testing. |
| `postinst.sh` | Post-install hook for packaging. |
| `publish-release.sh` | Push GitHub release assets + Pages output. |
| `setup.sh` | Prepare dependencies for build. |
| `sync-upstream.sh` | Pull upstream release metadata. |
| `validate-repos.sh` | Sanity checks for generated repos. |
