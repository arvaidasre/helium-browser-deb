# Archived Workflows

These workflows have been replaced by a simplified, unified automation system.

## Replacement Structure

| Old Workflow | Replaced By | Notes |
|-------------|-------------|-------|
| `build-and-release.yml` | `auto-build.yml` | Now runs every 3 hours automatically |
| `build-and-update-repo.yml` | `auto-build.yml` | Combined into single workflow |
| `build-prerelease.yml` | `auto-build.yml` | Pre-release detection is now automatic |
| `update-repos.yml` | `auto-build.yml` | Deploy happens after build automatically |
| `hourly-cron.yml` | `healthcheck.yml` | Improved healthcheck with auto-repair |

## Current Active Workflows

1. **`auto-build.yml`** - Main automation:
   - Runs every 3 hours
   - Checks upstream for new releases
   - Builds DEB and RPM packages
   - Creates GitHub release
   - Deploys to GitHub Pages

2. **`healthcheck.yml`** - Monitoring:
   - Runs every hour
   - Checks if repos are accessible
   - Auto-triggers rebuild if broken

3. **`cleanup.yml`** - Maintenance:
   - Runs weekly (Sunday 2:00 UTC)
   - Removes old releases
   - Keeps last 5 stable releases

## Archived Date

2025-01-13
