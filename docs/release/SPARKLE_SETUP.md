# Sparkle Auto-Update Setup Guide

This guide covers setting up and using Sparkle auto-updates for ClaudeBar.

## Overview

ClaudeBar uses [Sparkle](https://sparkle-project.org/) for automatic updates. When a new version is released, users are notified and can update with one click.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   ClaudeBar     │────▶│   appcast.xml    │────▶│  GitHub Release │
│   (checks)      │     │  (GitHub Pages)  │     │  (downloads)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

- **appcast.xml**: XML feed listing available versions (hosted on GitHub Pages)
- **EdDSA Signature**: Cryptographic signature ensuring update authenticity
- **GitHub Releases**: Hosts the actual `.zip` download files

## Configuration

### Info.plist Keys

| Key | Value | Description |
|-----|-------|-------------|
| `SUFeedURL` | `https://tddworks.github.io/ClaudeBar/appcast.xml` | Update feed location |
| `SUPublicEDKey` | `2Kn6vvvrrNqgAWrzOiq5Ae+abMjEqlu2MOOM/YBlsw0=` | Public key for signature verification |

### GitHub Secrets

| Secret | Description |
|--------|-------------|
| `SPARKLE_EDDSA_PRIVATE_KEY` | Private key for signing updates |

## Development

### Running with Sparkle Enabled

Sparkle requires a proper `.app` bundle. In development, Sparkle is disabled when running via `swift run` since there's no bundle structure.

For release builds, the GitHub Actions workflow creates the proper `.app` bundle with Sparkle fully functional.

### Running from Xcode/swift run

When running directly via `swift run` or Xcode, Sparkle is automatically disabled because there's no proper app bundle. You'll see:

```
SparkleUpdater: Not running from app bundle, updater disabled
```

This is expected. The Settings view will show "Updates unavailable in debug builds".

### Testing Updates

1. Build a test version with a lower version number
2. Create a release with a higher version number
3. Run the test version and click "Check for Updates"

## Release Process

The GitHub Actions workflow (`release.yml`) automatically:

1. Builds universal binary (arm64 + x86_64)
2. Creates signed and notarized `.app` bundle
3. Generates EdDSA signature for the ZIP
4. Creates `appcast.xml` with version info
5. Deploys appcast to GitHub Pages
6. Uploads assets to GitHub Releases

### Manual Release

```bash
# Tag and push
git tag v1.2.0
git push origin v1.2.0
```

The workflow triggers automatically on version tags.

## Key Generation (One-Time Setup)

If you need to regenerate keys:

```bash
# Generate new EdDSA key pair
./scripts/sparkle-setup.sh

# Output:
# - Public key: Add to Info.plist (SUPublicEDKey)
# - Private key: Add to GitHub Secrets (SPARKLE_EDDSA_PRIVATE_KEY)
```

⚠️ **Warning**: Changing keys invalidates all previous releases. Users on old versions won't be able to update automatically.

## Appcast Format

The `appcast.xml` follows Sparkle 2.x format:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ClaudeBar Updates</title>
    <item>
      <title>Version 1.2.0</title>
      <pubDate>Wed, 25 Dec 2024 12:00:00 +0000</pubDate>
      <sparkle:version>1.2.0</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/.../ClaudeBar-1.2.0.zip"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
```

## Troubleshooting

### "Updates unavailable in debug builds"

This is normal when running via `swift run` or Xcode. Use `make run` instead.

### "No update found" when there should be one

1. Check that `appcast.xml` is deployed: https://tddworks.github.io/ClaudeBar/appcast.xml
2. Verify the version in appcast is higher than the running version
3. Check the EdDSA signature is valid

### Signature verification failed

The private key used to sign the release must match the public key in Info.plist. If keys were regenerated, ensure:
- `SUPublicEDKey` in Info.plist matches the new public key
- `SPARKLE_EDDSA_PRIVATE_KEY` secret contains the new private key

### Update downloads but won't install

- Ensure the app is properly code-signed and notarized
- Check that the ZIP contains a valid `.app` bundle
- Verify entitlements allow network access

## Files

| File | Purpose |
|------|---------|
| `Sources/App/SparkleUpdater.swift` | SwiftUI wrapper for Sparkle |
| `Sources/App/Info.plist` | Contains `SUFeedURL` and `SUPublicEDKey` |
| `docs/appcast.xml` | Update feed (deployed to GitHub Pages) |
| `.github/workflows/release.yml` | Automated release with appcast generation |
| `scripts/sparkle-setup.sh` | EdDSA key generation helper |
| `scripts/update-appcast.sh` | Appcast update script (appends versions) |

## References

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [EdDSA Signatures](https://sparkle-project.org/documentation/eddsa-migration/)
