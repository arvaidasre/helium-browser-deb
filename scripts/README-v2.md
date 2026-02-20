# Repository System v2

This directory contains the improved package building and repository generation system.

## What's New in v2

### ✨ Key Improvements

1. **GPG Package Signing**
   - DEB packages signed with `dpkg-sig` or `debsigs`
   - RPM packages signed with `rpmsign`
   - Repository metadata signed (APT Release/InRelease, RPM repomd.xml)

2. **Checksum Verification**
   - Automatic upstream tarball checksum verification
   - SHA256SUMS file generation for all packages
   - Signed checksum files

3. **Multi-Channel Support**
   - `stable/` — Stable releases only
   - `nightly/` — Daily builds from latest upstream

4. **Distribution-Specific Dependencies**
   - Ubuntu 20.04 vs 22.04 vs 24.04+ have different package names
   - Automatic dependency mapping based on target distro

5. **Improved Versioning**
   - Distro-specific iteration numbers (e.g., `1.2.3-1noble1`, `1.2.3-1jammy1`)
   - Nightly builds include date suffix

## Quick Start

### Setup GPG Key

```bash
# Generate new key
./scripts/utils/gpg-setup.sh generate

# Or import existing key
export GPG_PRIVATE_KEY="-----BEGIN PGP PRIVATE KEY-----..."
./scripts/utils/gpg-setup.sh import

# Export public key for distribution
./scripts/utils/gpg-setup.sh export site/public/HELIUM-GPG-KEY
```

### Build Packages

```bash
# Build stable channel
CHANNEL=stable ./scripts/build/build-v2.sh

# Build nightly channel
CHANNEL=nightly ./scripts/build/build-v2.sh

# Build all channels
./scripts/build/build-all.sh

# Force rebuild even if release exists
FORCE_BUILD=true ./scripts/build/build-v2.sh
```

### Generate Repositories

```bash
# Generate signed APT repository
./scripts/repo/apt-v2.sh site/public/apt

# Generate signed RPM repository
./scripts/repo/rpm-v2.sh site/public/rpm
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CHANNEL` | Build channel (`stable` or `nightly`) | `stable` |
| `GPG_PRIVATE_KEY` | GPG private key for signing | - |
| `GPG_KEY_ID` | Specific GPG key ID to use | Auto-detect |
| `FORCE_BUILD` | Force rebuild even if exists | `false` |
| `VERIFY_CHECKSUM` | Verify upstream checksums | `true` |
| `TARGET_DISTRO` | Target distro (`ubuntu`, `debian`, `fedora`) | `ubuntu` |
| `TARGET_CODENAME` | Target codename (`noble`, `jammy`, etc.) | `noble` |
| `APT_DISTS` | Space-separated APT dist list | `stable noble jammy focal bookworm bullseye` |

## File Structure

```
scripts/
├── build/
│   ├── build-v2.sh          # Main build script (v2)
│   ├── build-all.sh         # Build all channels
│   └── resources/
│       └── postinst.sh      # Post-install script
├── repo/
│   ├── apt-v2.sh            # Signed APT repo generator
│   └── rpm-v2.sh            # Signed RPM repo generator
├── lib/
│   ├── common.sh            # Shared utilities
│   └── deps-map.sh          # Dependency mappings
└── utils/
    ├── gpg-setup.sh         # GPG key management
    └── checksum-verify.sh   # Checksum verification
```

## Migration from v1

The v1 scripts (`build.sh`, `apt.sh`, `rpm.sh`) are still available for backward compatibility.
To fully migrate:

1. Set up GPG signing (optional but recommended)
2. Update CI to use `-v2` scripts
3. Update install instructions to mention GPG key import

## Security Notes

- **Always sign packages in CI/CD** — Never commit private keys to git
- Use GitHub Secrets or similar for `GPG_PRIVATE_KEY`
- Rotate GPG keys annually
- Keep key passphrase in separate secret if key is passphrase-protected
