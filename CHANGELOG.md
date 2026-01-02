# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.12] - 2026-01-02

### Added
- **Provider Enable/Disable**: Toggle individual AI providers on/off from Settings. Disabled providers are hidden from the menu bar and excluded from quota monitoring.
- **Copilot Credential Management**: GitHub Copilot now manages its own credentials (token and username) directly within the provider, making setup more intuitive.

### Changed
- **Simplified Architecture**: Streamlined codebase with cleaner separation of concerns
  - Views now consume domain models directly from `QuotaMonitor`
  - Provider settings persisted via injectable repositories for better testability
  - Credential management moved from global settings to individual providers

### Removed
- **Z.ai Demo Mode**: Removed demo mode toggle - Z.ai provider now always uses real credentials

### Fixed
- **Z.ai Icon**: Now displays the correct Z.ai provider icon

### Technical
- Introduced `ProviderSettingsRepository` protocol for provider enable/disable persistence
- Introduced `CredentialRepository` protocol for token/credential storage
- Moved `CopilotProvider` credentials from `AppSettings` to provider-owned state
- `QuotaMonitor` now owns `AIProviders` repository with delegation methods
- Removed `AppState` layer - views consume `QuotaMonitor` directly
- Added comprehensive test coverage for ZaiProvider (22 tests)
- Refactored tests to follow Chicago School TDD (state-based, no verify calls)

## [0.2.11] - 2026-01-01

### Added
- **Share Claude Pass**: Share referral links with friends to give them a free week of Claude Code! Click the gift icon (🎁) in the action bar when Claude is selected to copy or open your referral link.

### Improved
- **Cleaner Action Bar**: Share button is now a compact icon that fits seamlessly alongside Settings and Close buttons
- **Button Text Stability**: Fixed issue where action button labels could wrap to multiple lines

### Technical
- Added `ClaudePass` domain model with referral URL and optional pass count
- Implemented `ClaudePassProbe` that executes `claude /passes` and reads referral link from clipboard
- Added `ClaudePassProbing` protocol for testability with dependency injection
- Created `SharePassOverlay` view component with copy-to-clipboard and open-in-browser actions
- Extended `ClaudeProvider` with `fetchPasses()` method and guest pass state management
- Added share gradient to theme system for consistent styling
- Comprehensive test coverage (30 tests) for domain model, probe parsing, and provider integration

## [0.2.10] - 2025-12-31

### Improved
- **Z.ai Quota Reset Time**: Now displays when your Z.ai quota will reset, helping you plan your usage effectively

### Technical
- Added flexible date parsing for Z.ai API responses (supports ISO-8601 with timezone and milliseconds)

## [0.2.9] - 2025-12-31

### Added
- **Z.ai GLM Coding Plan Support**: Monitor your [Z.ai GLM Coding Plan](https://z.ai/subscribe) usage quota directly from the menu bar. Automatically detects Z.ai configuration in Claude Code settings and displays your 5-hour session limit and MCP usage in real-time.
- **Provider Icon**: New Z.ai icon with blue branding in the provider list

### Technical
- Implemented `ZaiUsageProbe` with Bearer authentication and config file parsing (supports `env` and `providers` formats)
- Added `ZaiProvider` domain model with observable state
- Added `QuotaType.timeLimit` for semantic mapping of time-based quotas (MCP usage)
- Comprehensive test coverage (27 tests) for parsing, behavior, and error handling

## [0.2.8] - 2025-12-30

### Fixed
- Bug fixes and improvements.

## [0.2.7] - 2025-12-29

### Fixed
- **Antigravity Quota Parsing**: Fixed issue where models with only reset time but no remaining fraction (like "Gemini 3 Flash") were incorrectly excluded from quota display. Missing `remainingFraction` now correctly indicates 0% remaining.

## [0.2.6] - 2025-12-29

### Improved
- **Cleaner Menu Layout**: Replaced scroll view with dynamic height layout for a smoother, more native menu bar experience
- **Smarter Quota Alerts**: Improved notification timing - alerts now request permission after the app fully launches, fixing issues on menu bar apps
- **Better Alert Messages**: Clearer, more actionable quota alert messages when your usage is running low

### Fixed
- **Notification Permission**: Fixed issue where notification permission requests were being denied on first launch

### Technical
- Refactored notification system with cleaner domain naming (`QuotaAlerter`, `QuotaStatusListener`)
- Merged notification infrastructure into single `QuotaAlerter` class for simpler architecture
- Added detailed authorization status logging for easier troubleshooting

## [0.2.5] - 2025-12-29

### Added
- **Google Antigravity Support**: Monitor your Antigravity AI assistant usage quota directly from the menu bar alongside Claude, Codex, Gemini, and GitHub Copilot
- **Local Server Detection**: Automatically detects running Antigravity language server and retrieves quota information via local API
- **Provider Icon**: New Antigravity icon in the provider list for easy identification

### Improved
- **Developer Documentation**: New TDD-based skill guide for adding AI providers, making it easier for contributors to add support for additional assistants
- **Secure Localhost Connections**: Added dedicated network client for handling self-signed certificates on localhost connections

### Technical
- Implemented `AntigravityUsageProbe` with process detection via `ps` and `lsof`
- Added CSRF token extraction from process arguments for secure API calls
- Created `InsecureLocalhostNetworkClient` adapter for self-signed cert handling
- Added `AntigravityProvider` domain model with observable state
- Comprehensive test coverage for process detection, API parsing, and error handling

## [0.2.4] - 2025-12-29

### Added
- **Dual-Output Logging**: Logs now write to both OSLog (for developers via Console.app) and persistent files (for users) at `~/Library/Logs/ClaudeBar/ClaudeBar.log`
- **Open Logs Button**: New "Open Logs Folder" button in Settings for easy access to log files when troubleshooting
- **Comprehensive Error Logging**: All AI provider probes now log detailed error information for easier debugging

### Improved
- **Better Troubleshooting**: Users can now share log files when reporting issues, making it easier to diagnose problems
- **Automatic Log Rotation**: Log files automatically rotate at 5MB to prevent disk space issues
- **Thread-Safe Logging**: File logging is designed for safe concurrent access

### Technical
- Added `FileLogger` with automatic directory creation and 5MB rotation
- Created `AppLog` facade that unifies OSLog and file output
- Debug level logs go to OSLog only; info/warning/error go to both outputs
- Added unit tests for ANSI stripping in log content

## [0.2.3] - 2025-12-28

### Added
- **Beta Updates Channel**: Opt into beta releases to get early access to new features before they're widely available
- **Dual Update Tracks**: Stable and beta releases now coexist - stable users get stable updates, beta users get the latest beta

### Improved
- **Smarter Update Feed**: The appcast now maintains both the latest stable and beta versions, ensuring you always get the right update for your preference
- **Reliable Version Detection**: Build numbers are now properly validated to prevent version confusion

### Technical
- Added comprehensive unit tests for update channel handling (17 test scenarios)
- Improved release workflow documentation for beta releases

## [0.2.2] - 2025-12-26

### Added
- Update Notification Badge: See a visual indicator on the settings button when a new version is available
- Version Info Display: View the available update version directly in the menu

## [0.2.1] - 2025-12-26

### Added
- **Auto-Update Toggle**: Control automatic update checks from Settings
- **Update Progress Indicator**: See visual feedback when checking for updates

### Improved
- **Smarter Update Checks**: Updates are now checked when you open the menu, giving you control instead of running in the background
- **Cleaner Update Dialog**: Release notes now display with better formatting
- **More Reliable CLI Interaction**: Better handling of CLI prompts and improved timeout for quota fetching

## [0.2.0] - 2025-12-25

### Added
- CHANGELOG.md as single source of truth for release notes
- `extract-changelog.sh` script to parse version-specific notes
- Sparkle checks for updates when menu opens (instead of automatic background checks)
- Improved release notes HTML formatting in update dialog

### Changed
- Release workflow uses CHANGELOG.md instead of auto-generated notes

### Fixed
- Sparkle warning about background app not implementing gentle reminders

## [0.1.0] - 2025-12-15

### Added
- Initial release
- Claude CLI usage monitoring
- Codex CLI usage monitoring
- Menu bar interface with quota display
- Automatic refresh every 5 minutes

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.2.12...HEAD
[0.2.12]: https://github.com/tddworks/ClaudeBar/compare/v0.2.11...v0.2.12
[0.2.11]: https://github.com/tddworks/ClaudeBar/compare/v0.2.10...v0.2.11
[0.2.10]: https://github.com/tddworks/ClaudeBar/compare/v0.2.9...v0.2.10
[0.2.9]: https://github.com/tddworks/ClaudeBar/compare/v0.2.8...v0.2.9
[0.2.8]: https://github.com/tddworks/ClaudeBar/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/tddworks/ClaudeBar/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/tddworks/ClaudeBar/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/tddworks/ClaudeBar/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/tddworks/ClaudeBar/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/tddworks/ClaudeBar/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/tddworks/ClaudeBar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/tddworks/ClaudeBar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tddworks/ClaudeBar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tddworks/ClaudeBar/releases/tag/v0.1.0
