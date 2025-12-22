# ClaudeBar

[![Build](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml)
[![Tests](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/tddworks/ClaudeBar/graph/badge.svg)](https://codecov.io/gh/tddworks/ClaudeBar)
[![Latest Release](https://img.shields.io/github/v/release/tddworks/ClaudeBar)](https://github.com/tddworks/ClaudeBar/releases/latest)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015-blue.svg)](https://developer.apple.com)

A macOS menu bar application that monitors AI coding assistant usage quotas. Keep track of your Claude, Codex, and Gemini usage at a glance.

<p align="center">
  <img src="docs/Screenshot-dark.png" alt="ClaudeBar Dark Mode" width="380"/>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/Screenshot-light.png" alt="ClaudeBar Light Mode" width="380"/>
</p>
<p align="center">
  <em>Dark Mode &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Light Mode</em>
</p>

## Features

- **Multi-Provider Support** - Monitor Claude, Codex, and Gemini quotas in one place
- **Real-Time Quota Tracking** - View Session, Weekly, and Model-specific usage percentages
- **Light & Dark Themes** - Automatically adapts to your system appearance
- **Visual Status Indicators** - Color-coded progress bars (green/yellow/red) show quota health
- **System Notifications** - Get alerted when quota status changes to warning or critical
- **Auto-Refresh** - Automatically updates quotas at configurable intervals
- **Keyboard Shortcuts** - Quick access with `⌘D` (Dashboard) and `⌘R` (Refresh)

## Quota Status Thresholds

| Remaining | Status | Color |
|-----------|--------|-------|
| > 50% | Healthy | Green |
| 20-50% | Warning | Yellow |
| < 20% | Critical | Red |
| 0% | Depleted | Gray |

## Requirements

- macOS 15+
- Swift 6.2+
- CLI tools installed for providers you want to monitor:
  - [Claude CLI](https://claude.ai/code) (`claude`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)

## Installation

### Download (Recommended)

Download the latest release from [GitHub Releases](https://github.com/tddworks/ClaudeBar/releases/latest):

- **DMG**: Open and drag ClaudeBar.app to Applications
- **ZIP**: Unzip and move ClaudeBar.app to Applications

Both are code-signed and notarized for Gatekeeper.

### Build from Source

```bash
git clone https://github.com/tddworks/ClaudeBar.git
cd ClaudeBar
swift build -c release
```

## Usage

```bash
swift run ClaudeBar
```

The app will appear in your menu bar. Click to view quota details for each provider.

## Development

```bash
# Build the project
swift build

# Run all tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Run a specific test
swift test --filter "QuotaMonitorTests"
```

## Architecture

ClaudeBar uses a layered architecture with protocol-based dependency injection:

```
┌─────────────────────────────────────────────────┐
│                   App Layer                     │
│     SwiftUI Views + @Observable AppState        │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│                 Domain Layer                    │
│  Models: UsageQuota, UsageSnapshot, QuotaStatus │
│  Protocols: UsageProbe, StatusChangeObserver    │
│  Services: QuotaMonitor (Actor)                 │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│              Infrastructure Layer               │
│  Probes: ClaudeUsageProbe, CodexUsageProbe, etc │
│  Adapters: Pure 3rd-party wrappers (no coverage)│
└─────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Rich Domain Models** - Business logic lives in domain models, not ViewModels
- **Actor-Based Concurrency** - Thread-safe state management with Swift actors
- **Protocol-Based DI** - `@Mockable` protocols enable testability without real CLI/network
- **Adapters Folder** - Pure 3rd-party wrappers excluded from code coverage
- **No ViewModel Layer** - SwiftUI views directly consume domain models

## Dependencies

- [Sparkle](https://sparkle-project.org/) - Auto-update framework
- [Mockable](https://github.com/Kolos65/Mockable) - Protocol mocking for tests

## Releasing

Releases are automated via GitHub Actions. Push a version tag to create a new release.

**For detailed setup instructions, see [docs/RELEASE_SETUP.md](docs/RELEASE_SETUP.md).**

### Quick Start

1. **Configure GitHub Secrets** (see [full guide](docs/RELEASE_SETUP.md)):

   | Secret | Description |
   |--------|-------------|
   | `APPLE_CERTIFICATE_P12` | Developer ID certificate (base64) |
   | `APPLE_CERTIFICATE_PASSWORD` | Password for .p12 |
   | `APP_STORE_CONNECT_API_KEY_P8` | API key (base64) |
   | `APP_STORE_CONNECT_KEY_ID` | Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |

2. **Verify your certificate**:
   ```bash
   ./scripts/verify-p12.sh /path/to/certificate.p12
   ```

3. **Create a release**:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

The workflow will automatically build, sign, notarize, and publish to GitHub Releases.

## License

MIT
