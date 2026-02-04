# Release Setup Guide

This guide explains how to set up the GitHub secrets required for automated releases of ClaudeBar.

## Overview

The release workflow requires **5 secrets** to be configured in GitHub:

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE_P12` | Developer ID Application certificate (base64) |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APP_STORE_CONNECT_API_KEY_P8` | App Store Connect API key (base64) |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |

## Prerequisites

- Apple Developer Program membership ($99/year)
- macOS with Keychain Access
- Access to [Apple Developer Portal](https://developer.apple.com/account)
- Access to [App Store Connect](https://appstoreconnect.apple.com)

---

## Part 1: Developer ID Application Certificate

This certificate is used to sign the app for distribution outside the Mac App Store.

### Step 1.1: Create a Certificate Signing Request (CSR)

1. Open **Keychain Access** on your Mac
2. Go to **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**
3. Fill in:
   - **User Email Address**: Your email
   - **Common Name**: Your name
   - **CA Email Address**: Leave empty
   - **Request is**: Select **Saved to disk**
4. Click **Continue** and save the `.certSigningRequest` file

### Step 1.2: Create the Certificate in Apple Developer Portal

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click the **+** button to create a new certificate
3. Select **Developer ID Application** under "Software"
4. Click **Continue**
5. Upload the CSR file you created in Step 1.1
6. Click **Continue**
7. Download the certificate (`.cer` file)

### Step 1.3: Install the Certificate

1. Double-click the downloaded `.cer` file
2. It will be added to your **login** keychain in Keychain Access
3. Verify: Open Keychain Access → **My Certificates** → look for `Developer ID Application: Your Name (TEAMID)`

### Step 1.4: Export as .p12

1. In Keychain Access, go to **My Certificates**
2. Find `Developer ID Application: Your Name (TEAMID)`
   - It should have a **▶ disclosure triangle** showing a private key underneath
3. Click on the **certificate** (not the key)
4. Go to **File → Export Items** (or right-click → Export)
5. Choose **Personal Information Exchange (.p12)** format
6. Save the file and **enter a password** when prompted
7. Remember this password - you'll need it for `APPLE_CERTIFICATE_PASSWORD`

> **Troubleshooting**: If you can only export as `.cer` (not `.p12`), the private key is missing. See [Certificate Troubleshooting](#certificate-troubleshooting) below.

### Step 1.5: Base64 Encode the .p12

```bash
base64 -i /path/to/certificate.p12 | tr -d '\n' | pbcopy
```

This copies the base64-encoded certificate to your clipboard.

### Step 1.6: Add to GitHub Secrets

1. Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add:
   - **Name**: `APPLE_CERTIFICATE_P12`
   - **Value**: Paste the base64 string (Cmd+V)
4. Add another secret:
   - **Name**: `APPLE_CERTIFICATE_PASSWORD`
   - **Value**: The password you entered when exporting the .p12

---

## Part 2: App Store Connect API Key

This key is used for notarizing the app with Apple.

### Step 2.1: Create an API Key

1. Go to https://appstoreconnect.apple.com/access/api
2. Click **Keys** tab (or **Generate API Key** if first time)
3. Click the **+** button to create a new key
4. Enter a **Name** (e.g., "GitHub Actions")
5. Select **Developer** access role
6. Click **Generate**

### Step 2.2: Download and Note the Details

After creating the key:

1. **Download the API Key** (`.p8` file)
   - ⚠️ **Important**: You can only download this ONCE! Save it securely.
2. Note the **Key ID** (e.g., `6X3CMK22CY`)
3. Note the **Issuer ID** at the top of the page (UUID format like `12345678-1234-1234-1234-123456789012`)

### Step 2.3: Base64 Encode the .p8

```bash
base64 -i /path/to/AuthKey_XXXXXX.p8 | tr -d '\n' | pbcopy
```

### Step 2.4: Add to GitHub Secrets

Add these three secrets:

| Secret Name | Value |
|-------------|-------|
| `APP_STORE_CONNECT_API_KEY_P8` | The base64-encoded .p8 content |
| `APP_STORE_CONNECT_KEY_ID` | The Key ID (e.g., `6X3CMK22CY`) |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID (UUID) |

---

## Part 3: Verify Your Setup

### Verify the .p12 Certificate

Use the verification script:

```bash
./scripts/verify-p12.sh /path/to/certificate.p12
```

Expected output:
```
PASS: P12 file is valid
PASS: Found 1 certificate(s)
PASS: Found 1 private key(s)
PASS: Certificate is 'Developer ID Application' type
PASS: Certificate is valid for XXX more days
SUCCESS: P12 file contains both certificate and private key
```

### Verify the .p8 API Key

```bash
# Check the file looks correct
head -1 /path/to/AuthKey_XXXXXX.p8
# Should output: -----BEGIN PRIVATE KEY-----

tail -1 /path/to/AuthKey_XXXXXX.p8
# Should output: -----END PRIVATE KEY-----
```

### Verify GitHub Secrets

Your repository secrets should look like:

![GitHub Secrets](https://docs.github.com/assets/images/help/repository/repository-settings-secrets.png)

- `APPLE_CERTIFICATE_P12` ✓
- `APPLE_CERTIFICATE_PASSWORD` ✓
- `APP_STORE_CONNECT_API_KEY_P8` ✓
- `APP_STORE_CONNECT_KEY_ID` ✓
- `APP_STORE_CONNECT_ISSUER_ID` ✓

---

## Part 4: Create a Release

Once all secrets are configured, follow this workflow to create a release.

### Step 1: Write Release Notes in CHANGELOG.md

Before creating a release, update `CHANGELOG.md` with the changes for this version:

```markdown
## [Unreleased]

## [1.0.0] - 2025-12-25

### Added
- New feature X that does Y
- Better quota visualization

### Changed
- Improved performance of quota refresh

### Fixed
- Memory leak when switching providers
```

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/):
- `### Added` - New features
- `### Changed` - Changes to existing functionality
- `### Deprecated` - Features to be removed
- `### Removed` - Removed features
- `### Fixed` - Bug fixes
- `### Security` - Security fixes

### Step 2: Commit the Changelog

```bash
git add CHANGELOG.md
git commit -m "docs: add release notes for v1.0.0"
git push origin main
```

### Step 3: Create and Push the Tag

**Option A: Tag-based Release**

```bash
# Stable release
git tag v1.0.0
git push origin v1.0.0

# Beta release
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1

# Alpha or release candidate
git tag v2.0.0-alpha.1
git tag v2.0.0-rc.1
```

**Option B: Manual Release (workflow_dispatch)**

1. Go to **Actions** → **Release** workflow
2. Click **Run workflow**
3. Enter the version (e.g., `1.0.0` or `1.0.0-beta.1`)
4. Click **Run workflow**

### How Release Notes Flow

```
CHANGELOG.md (you write here)
       │
       ▼
extract-changelog.sh (extracts version section)
       │
       ├──────────────────┬──────────────────┐
       ▼                  ▼                  ▼
GitHub Release     appcast.xml        In-app updates
(What's New)       (Sparkle feed)     (shown to users)
```

The CI pipeline automatically:
1. Extracts release notes for your version from `CHANGELOG.md`
2. Includes them in the GitHub Release under "What's New"
3. Includes them in `appcast.xml` for Sparkle auto-updates

### Supported Version Formats

| Format | Example | Release Type |
|--------|---------|--------------|
| `X.Y.Z` | `1.0.0` | Stable |
| `X.Y.Z-beta` | `1.0.0-beta` | Pre-release |
| `X.Y.Z-beta.N` | `1.0.0-beta.3` | Pre-release |
| `X.Y.Z-alpha.N` | `2.0.0-alpha.1` | Pre-release |
| `X.Y.Z-rc.N` | `2.0.0-rc.1` | Pre-release |

Pre-releases are automatically flagged on GitHub and won't appear as the "latest" release.

### What the CI Does

The GitHub Actions workflow will automatically:
1. Build the app for Intel and Apple Silicon
2. Sign with your Developer ID certificate
3. Notarize with Apple
4. Extract release notes from CHANGELOG.md
5. Create a GitHub release with DMG and ZIP
6. Update appcast.xml for Sparkle auto-updates
7. Mark as pre-release if version contains `-`

> **Note:** Homebrew Cask updates happen automatically! BrewTestBot monitors GitHub releases and creates PRs to update the cask every ~3 hours. No manual action needed.

---

## Part 5: Beta Channel Updates

ClaudeBar uses Sparkle's channel feature to support beta updates. Users can opt into beta releases via Settings.

### How Beta Channels Work

1. **Appcast Structure**: The appcast maintains BOTH the latest stable AND latest beta versions:
   ```xml
   <channel>
       <item>  <!-- Latest beta (if any) -->
           <sparkle:channel>beta</sparkle:channel>
           ...
       </item>
       <item>  <!-- Latest stable -->
           <!-- No channel tag -->
           ...
       </item>
   </channel>
   ```

2. **Client-Side Filtering**:
   - **Beta OFF**: Sparkle only shows items WITHOUT `<sparkle:channel>` tag (stable only)
   - **Beta ON**: Sparkle shows items with channel=beta AND items without channel tag

3. **Version Comparison**: Sparkle compares `sparkle:version` (build number), not version strings. Build numbers always increase across all releases.

### Version Update Scenarios

The following table documents all supported update scenarios:

| # | User Version | Appcast Contains | Beta Setting | Expected Result | Explanation |
|---|--------------|------------------|--------------|-----------------|-------------|
| 1 | 1.0.0 | 1.0.0 only | Either | No update | Already on latest |
| 2 | 1.0.0 | 1.0.1-beta + 1.0.0 | ON | Get 1.0.1-beta | Beta enabled, newer beta available |
| 3 | 1.0.0 | 1.0.1-beta + 1.0.0 | OFF | No update | Beta filtered out, already on latest stable |
| 4 | 1.0.1-beta | 1.0.1 + 1.0.1-beta | Either | Get 1.0.1 | Stable has higher build number, always preferred |
| 5 | 1.0.1 | 1.0.2-beta + 1.0.1 | ON | Get 1.0.2-beta | Beta enabled, newer beta available |
| 6 | 1.0.1 | 1.0.2-beta + 1.0.1 | OFF | No update | Beta filtered out, already on latest stable |
| 7 | 1.0.0 | 1.0.2-beta + 1.0.1 | OFF | Get 1.0.1 | Beta filtered out, but stable 1.0.1 available |
| 8 | 1.0.0 | 1.0.2-beta + 1.0.1 | ON | Get 1.0.2-beta | Both visible, beta is newest |

### Key Behaviors

1. **Stable always has higher build number than its beta**: When releasing 1.0.1 stable after 1.0.1-beta, the stable gets a higher build number (e.g., 102 vs 101). This ensures beta users automatically upgrade to stable.

2. **Appcast retains both versions**: The `update-appcast.sh` script maintains both latest stable and latest beta, ensuring:
   - Stable users always see stable updates (even when betas exist)
   - Beta users see both and get the newest version

3. **No downgrade from stable to beta**: Since stable versions have higher build numbers than their corresponding betas, Sparkle won't offer a beta "upgrade" to a stable user on the same version.

### Release Workflow Examples

**Scenario A: Regular stable release**
```
1. v1.0.0 stable → appcast: [1.0.0]
2. v1.0.1 stable → appcast: [1.0.1]
   All users get 1.0.1
```

**Scenario B: Beta then stable**
```
1. v1.0.0 stable  → appcast: [1.0.0]
2. v1.0.1-beta    → appcast: [1.0.1-beta, 1.0.0]
   Beta users: get 1.0.1-beta
   Stable users: stay on 1.0.0
3. v1.0.1 stable  → appcast: [1.0.1, 1.0.1-beta]
   All users: get 1.0.1 (higher build number)
```

**Scenario C: Multiple betas**
```
1. v1.0.0 stable  → appcast: [1.0.0]
2. v1.0.1-beta.1  → appcast: [1.0.1-beta.1, 1.0.0]
3. v1.0.1-beta.2  → appcast: [1.0.1-beta.2, 1.0.0]
   Beta users: upgrade to 1.0.1-beta.2
   Stable users: stay on 1.0.0
4. v1.0.1 stable  → appcast: [1.0.1, 1.0.1-beta.2]
   All users: get 1.0.1
```

---

## Part 6: Homebrew Cask (Automatic)

ClaudeBar is available on [Homebrew Cask](https://formulae.brew.sh/cask/claudebar) and **updates automatically**.

### How It Works

The cask has a `livecheck` block that monitors GitHub releases. Homebrew's **BrewTestBot** automatically:
1. Detects new releases on GitHub every ~3 hours
2. Downloads the DMG and calculates SHA256
3. Creates a PR to update the cask formula
4. Merges it after CI passes

**No manual action is required** for Homebrew updates.

### Checking Homebrew Status

After releasing a new version, you can check the cask status:

```bash
# Check current Homebrew version
brew info --cask claudebar

# See the cask formula
brew cat claudebar
```

The Homebrew version typically updates within a few hours of a GitHub release.

### Manual Update (If Needed)

In rare cases where the automatic update doesn't work:

```bash
# Create a PR to update the cask
brew bump-cask-pr claudebar
```

Note: This will fail if BrewTestBot has already created a PR.

---

## Troubleshooting

### Certificate Troubleshooting

#### "Cannot export as .p12" - Only .cer option available

The private key is not associated with the certificate. This happens when:
- The certificate was created on a different Mac
- The private key was deleted

**Solution A**: Find the original Mac where the CSR was created and export from there.

**Solution B**: Create a new certificate:
1. Revoke the old certificate in Apple Developer Portal
2. Create a new CSR on your current Mac
3. Create a new Developer ID Application certificate
4. Export the new certificate as .p12

#### Certificate and key are separate in Keychain

If you see the certificate and private key as separate items:

1. Export the certificate as `.cer`
2. Export the private key as `.p12`
3. Combine them using the script:
   ```bash
   ./scripts/combine-cert-key.sh cert.cer key.p12 combined.p12
   ```

#### "0 valid identities found" in GitHub Actions

The certificate chain is incomplete. Make sure:
- You're using a **Developer ID Application** certificate (not Mac Developer or Apple Distribution)
- The .p12 contains both the certificate AND private key

### Notarization Troubleshooting

#### "invalidPrivateKeyContents"

The API key is corrupted or incorrectly encoded.

1. Re-download the .p8 file from App Store Connect (if you still can)
2. Re-encode: `base64 -i AuthKey_XXX.p8 | tr -d '\n' | pbcopy`
3. Update the `APP_STORE_CONNECT_API_KEY_P8` secret

#### "Invalid issuer" or authentication errors

Check that:
- `APP_STORE_CONNECT_KEY_ID` matches the Key ID exactly
- `APP_STORE_CONNECT_ISSUER_ID` is the Issuer ID (UUID), not the Key ID
- The API key has **Developer** or **Admin** role

---

## Quick Reference

### Release Workflow Cheat Sheet

```bash
# 1. Update CHANGELOG.md with release notes (use your editor)

# 2. Preview what will be extracted for a version
./scripts/extract-changelog.sh 1.0.0

# 3. Commit changelog and create release
git add CHANGELOG.md
git commit -m "docs: add release notes for v1.0.0"
git push origin main

# 4. Create and push the tag
git tag v1.0.0 && git push origin v1.0.0

# Create a beta release
git tag v1.0.0-beta.1 && git push origin v1.0.0-beta.1
```

### Certificate Commands

```bash
# Base64 encode certificate
base64 -i certificate.p12 | tr -d '\n' | pbcopy

# Base64 encode API key
base64 -i AuthKey_XXXX.p8 | tr -d '\n' | pbcopy

# Verify .p12 file
./scripts/verify-p12.sh certificate.p12

# Combine separate cert and key
./scripts/combine-cert-key.sh cert.cer key.p12 combined.p12

# Check local signing identities
security find-identity -v -p codesigning
```

### Homebrew Commands

```bash
# Check current Homebrew Cask version
brew info --cask claudebar

# Install from Homebrew
brew install --cask claudebar

# View cask formula
brew cat claudebar
```

### Links

- [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates)
- [App Store Connect API Keys](https://appstoreconnect.apple.com/access/api)
- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Homebrew Cask claudebar](https://formulae.brew.sh/cask/claudebar)
