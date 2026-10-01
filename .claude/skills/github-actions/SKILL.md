---
name: github-actions
description: |
  Manage ClaudeBar's GitHub Actions CI/CD pipelines: build, test, and release workflows.
  Use this skill when:
  (1) Setting up secrets for CI/CD (certificate, API key, Sparkle key, Codecov)
  (2) Creating a new release — tag-based or manual workflow_dispatch
  (3) Triggering or explaining the build.yml, tests.yml, or release.yml workflows
  (4) Debugging release failures (signing, notarization, appcast)
  (5) Managing beta vs stable channels for Sparkle auto-updates
  (6) User says "release a new version", "push a tag", "set up CI secrets", "why did the release fail"
---

# ClaudeBar GitHub Actions

Three workflows live in `.github/workflows/`. See reference files for setup and troubleshooting.

## Workflows at a Glance

| Workflow | Trigger | Runner | Purpose |
|----------|---------|--------|---------|
| `build.yml` | push/PR to main, develop | macos-15 | Debug + release build verification |
| `tests.yml` | push/PR to main, develop | macos-26 | Unit tests + Codecov coverage upload |
| `release.yml` | `v*` tag push OR manual | macos-15 | Sign → notarize → DMG → GitHub release → appcast |

## Create a Release

**Option A — Tag (recommended):**

```bash
# 1. Update CHANGELOG.md with release notes for this version
# 2. Commit and push
git add CHANGELOG.md
git commit -m "docs: add release notes for v1.2.0"
git push origin main

# 3. Tag and push — this triggers release.yml automatically
git tag v1.2.0 && git push origin v1.2.0

# Beta / pre-release (automatically flagged on GitHub)
git tag v1.2.0-beta.1 && git push origin v1.2.0-beta.1
```

**Option B — Manual dispatch:**

1. Go to **Actions → Release → Run workflow**
2. Enter version (e.g. `1.2.0` or `1.2.0-beta.1`)
3. Optionally toggle `publish_appcast` and `debug`

**Supported version formats:** `X.Y.Z`, `X.Y.Z-beta`, `X.Y.Z-beta.N`, `X.Y.Z-alpha.N`, `X.Y.Z-rc.N`

## Secrets Required

| Secret | Required For | See |
|--------|-------------|-----|
| `APPLE_CERTIFICATE_P12` | Code signing | [secrets-setup.md](references/secrets-setup.md) |
| `APPLE_CERTIFICATE_PASSWORD` | Code signing | [secrets-setup.md](references/secrets-setup.md) |
| `APP_STORE_CONNECT_API_KEY_P8` | Notarization | [secrets-setup.md](references/secrets-setup.md) |
| `APP_STORE_CONNECT_KEY_ID` | Notarization | [secrets-setup.md](references/secrets-setup.md) |
| `APP_STORE_CONNECT_ISSUER_ID` | Notarization | [secrets-setup.md](references/secrets-setup.md) |
| `SPARKLE_EDDSA_PRIVATE_KEY` | In-app auto-updates | [secrets-setup.md](references/secrets-setup.md) |
| `CODECOV_TOKEN` | Coverage upload | [secrets-setup.md](references/secrets-setup.md) |
| `APP_IDENTITY` | Optional signing override | [secrets-setup.md](references/secrets-setup.md) |

## What the Release Pipeline Does

```
git tag v1.2.0
      │
      ▼
release.yml
  1. Extract + validate version (SemVer)
  2. Update Info.plist (CFBundleShortVersionString + CFBundleVersion = run_number)
  3. tuist install → tuist generate
  4. xcodebuild archive (arm64 + x86_64, unsigned)
  5. Import Developer ID cert into temp keychain
  6. codesign with entitlements
  7. notarytool submit + staple
  8. Create ZIP + DMG (signed), SHA256 checksums
  9. Extract release notes from CHANGELOG.md
 10. Publish GitHub Release (draft: false)
 11. Generate Sparkle appcast with EdDSA signature
 12. Deploy appcast to GitHub Pages
```

## Debugging Failures

Enable verbose output via **manual dispatch → debug: true**. This prints:
- P12 certificate details and contents
- All identities in the signing keychain
- Certificate subject and expiry dates

For detailed troubleshooting: [release-workflow.md → Troubleshooting](references/release-workflow.md#troubleshooting)

## Beta Channel

Pre-release tags (`v1.2.0-beta.1`) automatically:
- Set GitHub release as `prerelease: true`
- Add `<sparkle:channel>beta</sparkle:channel>` to the appcast entry
- Are only offered to users with **Beta Updates** enabled in Settings

Stable releases always win over betas of the same version (stable gets higher build number).

See [release-workflow.md](references/release-workflow.md) for the full beta channel matrix.
