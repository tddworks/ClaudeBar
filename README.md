# ClaudeBar

[![Build](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/build.yml)
[![Tests](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml/badge.svg)](https://github.com/tddworks/ClaudeBar/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/tddworks/ClaudeBar/graph/badge.svg)](https://codecov.io/gh/tddworks/ClaudeBar)
[![Latest Release](https://img.shields.io/github/v/release/tddworks/ClaudeBar)](https://github.com/tddworks/ClaudeBar/releases/latest)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015-blue.svg)](https://developer.apple.com)
[![Homebrew](https://img.shields.io/badge/Homebrew-Install-brightgreen.svg)](https://formulae.brew.sh/cask/claudebar)

A macOS menu bar application that monitors AI coding assistant usage quotas. Keep track of your Claude, Codex, Gemini, GitHub Copilot, Antigravity, and Z.ai usage at a glance.

<p align="center">
  <img src="docs/Screenshot-dark.png" alt="ClaudeBar Dark Mode" width="380"/>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/Screenshot-light.png" alt="ClaudeBar Light Mode" width="380"/>
</p>
<p align="center">
  <em>Dark Mode &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Light Mode</em>
</p>

### CLI Theme

<p align="center">
  <img src="docs/Screenshot-cli-dark.png" alt="ClaudeBar CLI Theme" width="380"/>
</p>
<p align="center">
  <em>Minimalistic monochrome terminal aesthetic with classic green accents</em>
</p>

### Christmas Theme

<p align="center">
  <img src="docs/Christmas-theme.png" alt="ClaudeBar Christmas Theme" width="380"/>
</p>
<p align="center">
  <em>Festive holiday theme with snowfall animation - automatically enabled during the Christmas season!</em>
</p>

## Features

- **Multi-Provider Support** - Monitor Claude, Codex, Gemini, GitHub Copilot, Antigravity, and Z.ai quotas in one place
- **Provider Enable/Disable** - Toggle individual providers on/off from Settings to customize your monitoring
- **Real-Time Quota Tracking** - View Session, Weekly, and Model-specific usage percentages
- **Multiple Themes** - Light, Dark, CLI (terminal-style), and festive Christmas themes
- **Automatic Adaptation** - System theme follows your macOS appearance; Christmas auto-enables during the holiday season
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
  - [GitHub Copilot](https://github.com/features/copilot) - Configure credentials in Settings
  - [Antigravity](https://antigravity.google) - Auto-detected when running locally
  - [Z.ai](https://z.ai/subscribe) - Configure Claude Code with GLM Coding Plan endpoint

## Installation

### Homebrew

Install via [Homebrew](https://brew.sh).

```bash
brew install claudebar
```

### Download (Recommended)

Download the latest release from [GitHub Releases](https://github.com/tddworks/ClaudeBar/releases/latest):

- **DMG**: Open and drag ClaudeBar.app to Applications
- **ZIP**: Unzip and move ClaudeBar.app to Applications

Both are code-signed and notarized for Gatekeeper.

### Build from Source

```bash
git clone https://github.com/tddworks/ClaudeBar.git
cd ClaudeBar

# Install Tuist (if not installed)
brew install tuist

# Install dependencies and build
tuist install
tuist build -- -configuration Release
```

## Usage

After building, open the generated Xcode workspace and run the app:

```bash
tuist generate
open ClaudeBar.xcworkspace
```

Then press `Cmd+R` in Xcode to run. The app will appear in your menu bar. Click to view quota details for each provider.

## Development

The project uses [Tuist](https://tuist.io) for dependency management and Xcode project generation.

### Quick Start

```bash
# Install Tuist (if not installed)
brew install tuist

# Install dependencies
tuist install

# Generate Xcode project and open
tuist generate
open ClaudeBar.xcworkspace
```

### Build & Test

```bash
# Build the project
tuist build

# Run all tests
tuist test

# Run tests with coverage
tuist test --result-bundle-path TestResults.xcresult -- -enableCodeCoverage YES

# Build release configuration
tuist build -- -configuration Release
```

### SwiftUI Previews

After opening in Xcode, SwiftUI previews will work with `Cmd+Option+Return`. The project is configured with `ENABLE_DEBUG_DYLIB` for preview support.

## Architecture

> **Full documentation:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

ClaudeBar uses a **layered architecture** with `QuotaMonitor` as the single source of truth:

| Layer | Purpose |
|-------|---------|
| **App** | SwiftUI views consuming domain directly (no ViewModel) |
| **Domain** | Rich models, `QuotaMonitor`, repository protocols |
| **Infrastructure** | Probes, storage implementations, adapters |

### Key Design Decisions

- **Single Source of Truth** - `QuotaMonitor` owns all provider state
- **Repository Pattern** - Settings and credentials abstracted behind injectable protocols
- **Protocol-Based DI** - `@Mockable` protocols enable testability
- **Chicago School TDD** - Tests verify state changes, not method calls
- **No ViewModel/AppState** - Views consume domain directly

## Contributing

### Adding a New AI Provider

Use the **add-provider** skill to guide you through adding new providers with TDD:

```
Tell Claude Code: "I want to add a new provider for [ProviderName]"
```

The skill guides you through: Parsing Tests → Probe Tests → Implementation → Registration.

See `.claude/skills/add-provider/SKILL.md` for details and `AntigravityUsageProbe` as a reference implementation.

## Dependencies

- [Sparkle](https://sparkle-project.org/) - Auto-update framework
- [Mockable](https://github.com/Kolos65/Mockable) - Protocol mocking for tests
- [Tuist](https://tuist.io) - Xcode project generation (for SwiftUI previews)

## Releasing

Releases are automated via GitHub Actions. Push a version tag to create a new release.

**For detailed setup instructions, see [docs/release/RELEASE_SETUP.md](docs/release/RELEASE_SETUP.md).**

### Release Workflow

The workflow uses Tuist to generate the Xcode project:

```
Tag v1.0.0 → Update Info.plist → tuist generate → xcodebuild → Sign & Notarize → GitHub Release
```

Version is set in `Sources/App/Info.plist` and flows through to Sparkle auto-updates.

### Quick Start

1. **Configure GitHub Secrets** (see [full guide](docs/release/RELEASE_SETUP.md)):

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
