# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.12] - 2026-01-20

### Changed
- **Background Sync Disabled by Default**: Background sync is now disabled by default. Each Claude CLI spawn triggers a warmup session (even with zero prompts), and frequent background syncs can cause these sessions to stack up. The Claude Code team has addressed this in recent versions, so if you've updated to the latest Claude CLI, you can safely re-enable background sync in Settings → Background Sync.

## [0.3.6] - 2026-01-11

### Added
- **SwiftTerm Integration**: Added SwiftTerm terminal emulator library to properly render Claude CLI output. This fixes parsing issues with Claude Code v2.1.4+ which uses advanced terminal UI with cursor movements that previously corrupted captured output.

### Improved
- **Simplified Parsing**: Removed complex fuzzy matching and cursor movement heuristics. Terminal output is now properly rendered before parsing, producing clean text like a real terminal display.
- **Better Quota Accuracy**: Terminal rendering ensures "Current session" and other quota labels are parsed correctly even when the CLI uses cursor positioning to redraw the screen.

### Fixed
- **Sonnet Quota Display**: Fixed "Current week (Sonnet only)" being incorrectly labeled as "Opus" in the quota display. Sonnet and Opus quotas are now tracked and displayed separately.
- **Null Character Handling**: Fixed terminal buffer extraction to properly handle null characters from empty cells, which caused extracted text to include invisible padding.

### Technical
- Added SwiftTerm dependency (1.2.0+) for VT100/Xterm terminal emulation
- Created `TerminalRenderer` utility in `Sources/Infrastructure/Adapters/` that handles cursor movements, screen clearing, and ANSI escape sequences
- Replaced `stripANSICodes()` in `ClaudeUsageProbe` with `renderTerminalOutput()` using SwiftTerm
- Updated `Project.swift` to include SwiftTerm in Infrastructure target for Tuist builds
- Removed fuzzy regex matching (`matchesFuzzy`) - no longer needed with proper terminal rendering

## [0.3.4] - 2026-01-08

### Added
- **Background Sync**: Your quota data now syncs automatically in the background, so it's always fresh when you open the menu. No more waiting! Configure sync intervals (30s, 1min, 2min, or 5min) in Settings → Background Sync.
- **Fresh App Logo**: Updated app icon with a refreshed design.

### Improved
- **Better CLI Detection**: Fixed issues finding Claude, Codex, and other CLI tools on systems with custom shell configurations. The app now uses your login shell to properly resolve PATH ([#45](https://github.com/tddworks/ClaudeBar/issues/45)).

### Fixed
- **Update Window Focus**: The update dialog now properly comes to the front when checking for updates.

### Technical
- Added `backgroundSyncEnabled` and `backgroundSyncInterval` settings to `AppSettings`
- Implemented background sync lifecycle in `MenuContentView` with start/stop/restart controls
- Added Background Sync settings card to Settings UI with interval picker
- Uses existing `QuotaMonitor.startMonitoring()` infrastructure for efficient polling
- Added `shellPath()` to `InteractiveRunner` for accurate shell environment resolution

## [0.3.0] - 2026-01-05

### Added
- **Pluggable Theme System**: ClaudeBar now supports multiple visual themes with a protocol-based architecture. Switch themes instantly from Settings to match your workflow and preferences.
- **CLI Terminal Theme**: New monochrome, terminal-inspired theme for developers who prefer a classic command-line aesthetic. Features monospace fonts, green accents, and a retro terminal look.
- **Theme-Specific Menu Bar Icons**: Each theme can display its own custom menu bar icon, providing a cohesive visual experience across the entire app.

### Improved
- **Enhanced Christmas Theme**: Refreshed festive color palette with improved reds, greens, and golds. Updated gradients and glass effects for a more polished holiday feel.
- **Smoother UI**: Refined corner radius on cards and pills for a more consistent visual appearance across all themes.
- **Menu Width**: Adjusted menu content width for better readability.

### Fixed
- **Menu Bar Status Display**: The menu bar icon now correctly reflects the selected provider's status instead of showing incorrect state.

### Technical
- Introduced `AppThemeProvider` protocol for pluggable theme architecture
- Added `ThemeRegistry` for runtime theme management and discovery
- Created SwiftUI environment integration with `@Environment(\.appTheme)` support
- Implemented built-in themes: Dark, Light, CLI, Christmas, and System (auto-switching)
- Added `statusBarIconName` property to themes for custom menu bar icons
- Moved theme colors to static properties within theme structs for better encapsulation
- Added comprehensive theme system design documentation

## [0.2.15] - 2026-01-05

### Added
- **Claude API Billing Support**: Users with API Usage Billing accounts (pay-per-use) can now monitor their Claude usage. The app automatically detects billing plan type and uses the `/cost` command to display total cost and API duration when `/usage` is unavailable.
- **Z.ai Environment Variable Fallback**: Configure a custom environment variable for GLM authentication in Settings, useful when you have multiple API keys or non-standard setups.
- **Custom Z.ai Config Path**: Specify a custom path to your Z.ai configuration file if it's not in the default Claude Code settings location.
- **Copilot Environment Variable Support**: Configure a custom environment variable for GitHub Copilot authentication, with validation to ensure the variable exists.

### Improved
- **Easier Log Access**: "Open Logs" now opens the log file directly in TextEdit instead of the folder, making it quicker to view logs.
- **Z.ai Settings UI**: Added chevron indicator to show expand/collapse state for Z.ai configuration section.
- **Better Z.ai Error Messages**: Error messages now include the config path being used, making troubleshooting easier.
- **CLI Diagnostics**: When Claude CLI is not found, the app now logs PATH and CLAUDE_CONFIG_DIR environment variables to help diagnose installation issues.

### Fixed
- **UI Layout Issues** ([#40](https://github.com/tddworks/ClaudeBar/issues/40)): Fixed layout constraints that caused views to break on certain screen sizes.
- **Claude Detection for API Accounts** ([#37](https://github.com/tddworks/ClaudeBar/issues/37)): Fixed issue where users with API Usage Billing accounts couldn't see Claude quota information.

### Technical
- Extended `ProbeError` with `subscriptionRequired` case for API billing detection
- Implemented `/cost` command parsing with cost value and API duration extraction
- Added ISP-based repository hierarchy for provider-specific settings (`ZaiSettingsRepository`, `CopilotSettingsRepository`)
- Namespaced UserDefaults keys with `providerConfig.` prefix for cleaner storage
- Added `NotificationAlerter` unit tests
- Comprehensive test coverage for API billing detection and cost parsing

## [0.2.14] - 2026-01-03

### Fixed
- **Layout Constraint Crash**: Fixed potential crash from layout constraints in background views.

### Technical
- Added skill guides for bug fixing and improvements following Chicago School TDD

## [0.2.13] - 2026-01-02

### Improved
- **Settings Scrolling**: Settings view now scrolls on small screens, ensuring all options remain accessible regardless of display size.

### Fixed
- **Provider Selection After Restart**: Disabled providers no longer appear selected after app restart. The app now automatically switches to the first enabled provider.

### Technical
- `QuotaMonitor` now maintains selection invariants (auto-selects valid provider on init and when providers are disabled)
- Added `setProviderEnabled()` API for toggling providers with automatic selection handling

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

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.3.7...HEAD
[0.3.12]: https://github.com/tddworks/ClaudeBar/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/tddworks/ClaudeBar/compare/v0.3.4...v0.3.6
[0.3.4]: https://github.com/tddworks/ClaudeBar/compare/v0.3.0...v0.3.4
[0.3.0]: https://github.com/tddworks/ClaudeBar/compare/v0.2.15...v0.3.0
[0.2.15]: https://github.com/tddworks/ClaudeBar/compare/v0.2.14...v0.2.15
[0.2.14]: https://github.com/tddworks/ClaudeBar/compare/v0.2.13...v0.2.14
[0.2.13]: https://github.com/tddworks/ClaudeBar/compare/v0.2.12...v0.2.13
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
