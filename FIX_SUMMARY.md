# Fix for APT Repository Generation Failure

## Problem
The GitHub Actions workflow was failing with the error "No arm64 packages found in pool/main" when generating APT repository Packages files, even though both amd64 and arm64 DEB packages were present.

## Root Cause
The original `dpkg-scanpackages` pipeline was using stderr redirection (`2>&1`) which could mask error messages. More importantly, the awk filter was case-sensitive and if no packages matched, it created an empty file, causing the script to fail.

## Solution
Modified `scripts/publish/publish.sh` to:

1. **Generate full Packages file first**: Run `dpkg-scanpackages` once to generate a complete Packages index to temp files
2. **Detect architectures**: Check what architectures actually exist in the packages before filtering
3. **Case-insensitive matching**: Use `tolower()` in awk to handle any case variations in the Architecture field
4. **Better error messages**: Provide more specific error messages to help diagnose issues
5. **Cleanup temp files**: Remove temporary files after processing

## Changes Made

### scripts/publish/publish.sh
- Replaced the inline pipeline with a two-step process:
  1. Generate full Packages file to `/tmp/full_packages.txt`
  2. Filter by architecture using case-insensitive awk matching
- Added diagnostic logging to show detected architectures
- Added cleanup of temp files at end of function

### scripts/utils/check-package-arch.sh (new)
- Utility script to check actual architecture from DEB package control file
- Useful for debugging if packages have unexpected architecture values

## Testing
The fix can be tested by:
1. Running the `rebuild-release` workflow with `update_repos=true`
2. Or using the diagnostic script: `./scripts/utils/check-package-arch.sh <deb-file>`
