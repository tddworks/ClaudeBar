# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [0.4.43] - 2026-03-11

### Added
- **Daily Usage Report Cards**: See your daily Claude Code cost, token usage, and working time right in the menu bar. ClaudeBar now analyzes your local session files (`~/.claude/projects/`) and displays three new cards below the quota cards:
  - **Cost Usage** — Estimated daily spend based on token counts and Anthropic's published model pricing (Opus, Sonnet, Haiku)
  - **Token Usage** — Total tokens consumed (input, output, and cache)
  - **Working Time** — Time spent in Claude Code sessions, estimated from message timestamps
  - Each card shows a comparison delta vs the previous day (e.g., "Vs Mar 10 -$27.47 (4.9%)")
  - Only scans recently modified files for fast performance even with thousands of sessions

---

## [0.4.42] - 2026-03-09

---

## [0.4.41] - 2026-03-08

---

## [0.4.40] - 2026-03-04

### Fixed
- **Cursor Enterprise Plan Support**: Fixed quota monitoring for enterprise accounts where `limitType` is `"team"`. Previously the parser always threw `"No usage data found"` because `individualUsage.plan.limit` is `0` on enterprise plans. The parser now falls back to `breakdown.total` for the individual credit limit and reads `teamUsage.onDemand` as an additional team quota source (reported in [#136](https://github.com/tddworks/ClaudeBar/issues/136)).

## [0.4.38] - 2026-02-25

### Added
- **Claude Setup-Token Support**: ClaudeBar now recognizes users who authenticate via `claude setup-token`. The app loads the `CLAUDE_CODE_OAUTH_TOKEN` environment variable as a credential source and gracefully falls back to stored credentials (file/keychain) that have full scope, so quota monitoring continues to work seamlessly regardless of how you authenticated (contributed by [@brendandebeasi](https://github.com/brendandebeasi) in [#129](https://github.com/tddworks/ClaudeBar/pull/129)).

### Fixed
- **MiniMax Region Support**: MiniMax settings now include a region selector (International vs. China) to point to the correct API endpoint. Previously the app hardcoded the China-region URL (`minimaxi.com`), preventing international users from fetching quota data. Select your region in Settings → MiniMax to fix connection issues (contributed by [@BryanQQYue](https://github.com/BryanQQYue) in [#125](https://github.com/tddworks/ClaudeBar/issues/125)).

## [0.4.37] - 2026-02-24

### Fixed
- **Codex process leak**: Fixed a critical bug where ClaudeBar would spawn a new `codex app-server` process on every usage refresh without ever terminating it. Over time this caused thousands of orphaned processes that degraded system performance (reported in [#113](https://github.com/tddworks/ClaudeBar/issues/113)). The locally-created `ProcessRPCTransport` is now properly closed after each RPC call via `defer`.

## [0.4.36] - 2026-02-16

### Added
- **Cursor Support**: Monitor your [Cursor](https://cursor.com) IDE subscription usage (included requests and on-demand spending) directly from the menu bar. Supports Pro, Business, Free, and Ultra plans with automatic tier detection.
  - Reads auth token from Cursor's local SQLite database automatically
  - Calls `cursor.com/api/usage-summary` for real-time usage data
  - Displays monthly included requests and on-demand usage
- **Overview Mode AppLogo**: The header now displays the ClaudeBar logo when Overview mode is enabled, instead of the last selected provider's icon.

### Fixed
- **Cursor API parsing**: Fixed parsing to match the real Cursor API response structure (`individualUsage.plan` and `individualUsage.onDemand`).

### Technical
- Added `CursorProvider` domain model following Kiro/AmpCode pattern
- Added `CursorUsageProbe` with HTTP API + SQLite token extraction
- Added Cursor visual identity (icon, brand color, gradient)
- 15+ parsing tests covering all Cursor response formats

## [0.4.35] - 2026-02-15

### Added
- **Kiro Support**: Monitor your [Kiro](https://kiro.dev) (by AWS) AI coding assistant usage quotas via `kiro-cli`. Displays weekly bonus credits and monthly regular credits with reset time tracking.
  - Install with `uv tool install kiro-cli` and authenticate via Kiro IDE
  - Automatically parses usage data from `kiro-cli /usage` output

### Fixed
- **MiniMax Branding**: Renamed "MiniMaxi" to "MiniMax" for correct branding consistency (#116).

### Technical
- Added `KiroProvider` domain model and `KiroUsageProbe` with CLI output parsing
- Added `SimpleCLIExecutor` for lightweight Process-based CLI execution
- Migrated Kiro tests from XCTest to Swift Testing

## [0.4.34] - 2026-02-15

### Added
- **MiniMax Support**: Monitor your [MiniMax](https://www.minimax.io) Coding Plan usage quota directly from the menu bar. Queries the MiniMax API for remaining coding plan credits.
  - Configurable API key and environment variable support in Settings
  - Test connection button to verify API key

### Fixed
- **Docs**: Corrected release build command in CLAUDE.md and README (`-C Release` → `-configuration Release`).

### Technical
- Added `MiniMaxiProvider` domain model with API-based quota tracking
- Added `MiniMaxiUsageProbe` querying `/v1/api/openplatform/coding_plan/remains`
- Added `MiniMaxiSettingsRepository` sub-protocol for API key and env var configuration
- Parsing and probe unit tests

## [0.4.33] - 2026-02-14

### Added
- **Claude Code Session Tracking**: Real-time monitoring of Claude Code sessions via hooks. When Claude Code is running, ClaudeBar shows session status directly in the menu bar and popover:
  - **Menu bar indicator**: A terminal icon appears next to the quota icon with phase-colored status (green = active, blue = subagents working, orange = stopped)
  - **Session card**: Detailed session info in the popover showing phase, task count, active subagents, duration, and working directory
  - **System notifications**: Get notified when a session starts ("Claude Code Started") and finishes ("Claude Code Finished — Completed 3 tasks in 2m 5s")
- **Hook Settings**: New "Claude Code Hooks" section in Settings with a single toggle to enable/disable. Automatically installs/uninstalls hooks in `~/.claude/settings.json`. Server starts/stops reactively when the toggle changes.
- **Copilot Internal API Probe**: New dual probe mode for GitHub Copilot, supporting Business and Enterprise plans where the Billing API returns 404. Switchable in Settings between "Billing API" (default) and "Copilot API" (`copilot_internal/user`) modes.

### Fixed
- **HookHTTPServer deadlock**: Removed `queue.sync` calls inside NWListener callbacks that already run on the same serial queue, preventing a crash on startup.
- **Hook format**: Updated hook installer to use Claude Code's new matcher-based format (`{"matcher": ".*", "hooks": [...]}`) instead of the deprecated flat format.

### Technical
- Added `SessionEvent`, `ClaudeSession`, and `SessionMonitor` (`@MainActor`) domain models for session lifecycle tracking
- Added `HookHTTPServer` using Network.framework (`NWListener`) for localhost-only event reception on port 19847
- Added `SessionEventParser` for parsing Claude Code hook JSON payloads
- Added `HookInstaller` with atomic writes and corruption-safe JSON handling
- Added `PortDiscovery` for writing/reading `~/.claude/claudebar-hook-port`
- Added `HookSettingsRepository` protocol and `UserDefaults` implementation
- Added `CopilotProbeMode` enum, `CopilotInternalAPIProbe`, and dual probe support in `CopilotProvider`
- Added `com.apple.security.network.server` entitlement for `NWListener`
- Added `AppLog.hooks` logging category
- Extracted `ClaudeSession.Phase.label` and `.color` extensions to deduplicate phase display logic
- Added `HookConstants.defaultPort` as single source of truth for port 19847

## [0.4.32] - 2026-02-12

### Added
- **Overview Mode**: New "Overview" toggle in Settings to display all enabled providers at once in a single scrollable view. Ideal for juggling multiple AI assistants (Claude + Codex + Kimi + ...) throughout the day — see all your quotas at a glance without switching between pills.

### Technical
- Added `overviewModeEnabled` setting to `AppSettings` with UserDefaults persistence
- Added scrollable overview layout with per-provider sections reusing existing stat cards, capped at 80% screen height

## [0.4.31] - 2026-02-12

### Added
- **Kimi Support**: Monitor your [Kimi](https://www.kimi.com/code/console) AI coding assistant usage quota directly from the menu bar. Displays weekly quota and 5-hour session rate limit with automatic tier detection (Andante/Moderato/Allegretto).
- **Kimi Dual Probe Mode**: Kimi now supports both CLI and API modes, switchable in Settings:
  - **CLI Mode (Recommended)**: Launches the interactive `kimi` CLI and sends `/usage`. No Full Disk Access needed — just install `kimi` CLI (`uv tool install kimi-cli`).
  - **API Mode**: Calls the Kimi API directly using browser cookie authentication via [SweetCookieKit](https://github.com/steipete/SweetCookieKit). Requires Full Disk Access to read browser cookies.
- **Provider Icon**: New Kimi icon with blue/cyan branded styling in the provider list.

### Technical
- Added `SweetCookieKit` dependency for cross-browser cookie extraction
- Implemented `KimiCLIUsageProbe` with interactive CLI execution and `/usage` output parsing
- Implemented `KimiUsageProbe` (API mode) with Connect-RPC API integration and JWT session header extraction
- Implemented `KimiTokenProvider` with env var → browser cookie fallback chain
- Added `KimiProvider` domain model with dual-probe support (CLI + API) and probe mode switching
- Added `KimiProbeMode` enum and `KimiSettingsRepository` sub-protocol (ISP pattern)
- Added Kimi configuration card in Settings with CLI/API probe mode picker
- Added visual identity (icon, theme color, gradient) for Kimi provider
- Registered Kimi provider in `ClaudeBarApp` startup with both probes
- Comprehensive test coverage: CLI parsing tests (18), CLI probe behavior tests (6), API probe tests (8), provider domain tests (18)

## [0.4.28] - 2026-02-10

### Added
- **Amp Code Support**: Monitor your [Amp](https://ampcode.com) (by Sourcegraph) AI coding assistant usage quota directly from the menu bar. Automatically detects the `amp` CLI and displays your usage and plan tier.
- **Amp Tier Detection**: Automatically identifies your Amp subscription tier (Free, Pro, etc.) for accurate quota display.
- **Provider Icon**: New Amp icon with branded styling in the provider list.

### Improved
- **Privacy Protection**: Amp probe sanitizes personal information from log output to prevent PII leaks.
- **Probe Performance**: Optimized regex compilation in Amp probe for faster quota parsing.

### Technical
- Implemented `AmpCodeUsageProbe` with CLI output parsing and tier detection via regex
- Added `AmpCodeProvider` domain model with observable state and settings persistence
- Added visual identity (icon, theme color, gradient) for Amp provider
- Registered Amp provider in `ClaudeBarApp` startup
- Comprehensive test coverage for probe parsing (130+ lines), probe behavior (127+ lines), and tier detection

## [0.4.26] - 2026-02-09

### Added
- **Launch at Login**: New toggle in Settings to automatically start ClaudeBar when you log in to your Mac. Uses macOS native `SMAppService` — no helper app required.
- **Pace Tick Mark**: Visual tick mark below the consumption bar showing your expected usage pace. ([#96](https://github.com/tddworks/ClaudeBar/pull/96) - thanks [@frankhommers](https://github.com/frankhommers)!)

### Fixed
- **Claude API Cost Display**: API cost is now correctly converted from cents to dollars in Claude API mode. ([#95](https://github.com/tddworks/ClaudeBar/issues/95))

### Improved
- **README Screenshots**: Compressed screenshots from ~38 MB to ~2.8 MB for faster page loading on GitHub.

## [0.4.2] - 2026-02-04

### Added
- **Codex API Mode**: New alternative to RPC mode that fetches quota data directly via the ChatGPT backend API. Faster than RPC mode (no subprocess spawning), with automatic OAuth token refresh. Switch between modes in Settings → Codex Configuration.
- **Codex Configuration Card**: New settings panel to choose between RPC mode (default, uses `codex app-server` JSON-RPC) and API mode (direct HTTP API calls using OAuth credentials from `~/.codex/auth.json`).

### Improved
- **Codebase Organization**: Reorganized Infrastructure and Domain layers from mechanism-based grouping (`CLI/`, `Adapters/`, `AWS/`) to provider-based grouping (`Claude/`, `Codex/`, `Gemini/`, etc.), making it easier to find all files related to a specific provider.

### Technical
- Added `CodexAPIUsageProbe` calling `https://chatgpt.com/backend-api/wham/usage` with OAuth token refresh via `https://auth.openai.com/oauth/token`
- Added `CodexCredentialLoader` for loading OAuth credentials from `~/.codex/auth.json`
- Added `CodexProbeMode` enum (`.rpc`, `.api`) and `CodexSettingsRepository` protocol for probe mode persistence
- Extended `CodexProvider` with dual probe support (RPC + API) and mode switching
- Reorganized `Sources/Infrastructure/` into provider-level folders (`Claude/`, `Codex/`, `Gemini/`, `Copilot/`, `Antigravity/`, `Zai/`, `Bedrock/`, `Shared/`)
- Reorganized `Sources/Domain/Provider/` and `Tests/InfrastructureTests/` to mirror the same provider-first structure

## [0.4.1] - 2026-02-04

### Added
- **Remaining / Used Display Toggle**: Switch between "25% Remaining" and "75% Used" views for all quota cards. Choose whichever framing makes more sense for your workflow — see how much you have left, or how much you've consumed. Toggle in Settings → Quota Display.

### Technical
- Added `UsageDisplayMode` enum in Domain layer with `.remaining` and `.used` cases
- Added `displayPercent(mode:)` and `displayProgressPercent(mode:)` methods to `UsageQuota`
- Added `usageDisplayMode` to `AppSettings` with UserDefaults persistence (default: `.remaining`)
- Updated `WrappedStatCard` and `QuotaCardView` to use display mode for percentage and label
- Added "Quota Display" settings card with two-button toggle
- 12 new tests covering display mode enum, percent calculation, and progress bar behavior

## [0.4.0] - 2026-02-03

### Added
- **Claude API Mode**: New alternative to CLI mode that fetches quota data directly via Anthropic's OAuth API. Faster than CLI mode (no subprocess spawning), with automatic token refresh. Switch between modes in Settings → Claude Configuration.
- **Claude Configuration Card**: New settings panel to choose between CLI mode (default, uses `claude /usage` command) and API mode (direct HTTP API calls using OAuth credentials).
- **Copilot Manual Usage Override**: For users with organization-based Copilot subscriptions where API data isn't available, manually enter your usage from GitHub settings. Supports both request counts (e.g., "99") and percentages (e.g., "198%").
- **Copilot Monthly Limit Configuration**: Choose your Copilot plan tier (Free/Pro: 50, Business: 300, Enterprise: 1000, Pro+: 1500) for accurate quota calculations.
- **Over-Quota Display**: Negative percentages now display correctly when you've exceeded your quota limit (e.g., -98% when using 99 of 50 requests).

### Improved
- **Better Error Messages**: When Claude API session expires, shows user-friendly message: "Session expired. Run `claude` in terminal to log in again."
- **Gemini Quota Accuracy**: Falls back to any available GCP project when primary project isn't found, ensuring quota data is displayed.
- **Auto-Trust Probe Directory**: Automatically trusts the probe working directory when Claude CLI shows trust dialog, eliminating manual intervention.
- **CLAUDE_CONFIG_DIR Support**: Respects custom Claude configuration directory for trust file location.

### Fixed
- **Copilot Dashboard URL**: Now links directly to GitHub Copilot features page for easier usage viewing.
- **Copilot Usage Period Reset**: Manual usage entries automatically clear when billing period changes.
- **Schema Validation**: Guards against unexpected config file schemas to prevent crashes.

### Technical
- Added `ClaudeAPIUsageProbe` with OAuth token refresh via `https://platform.claude.com/v1/oauth/token`
- Added `ClaudeCredentialLoader` for loading OAuth credentials from `~/.claude/.credentials.json` or Keychain
- Added `ClaudeProbeMode` enum and `ClaudeSettingsRepository` protocol for probe mode persistence
- Extended `ClaudeProvider` with dual probe support (CLI + API) and mode switching
- Added `ProbeError.sessionExpired` case with user-friendly error description
- Migrated build system to Tuist for dependency management
- Updated aws-sdk-swift and SwiftTerm dependencies

## [0.3.15] - 2026-01-23

### Added
- **AWS Bedrock Support**: Monitor your AWS Bedrock AI usage directly from the menu bar. Track daily costs, token counts, and per-model breakdowns for your Claude, Llama, and other Bedrock models. ([#75](https://github.com/tddworks/ClaudeBar/pull/75) - thanks [@tomstetson](https://github.com/tomstetson)!)
- **Bedrock Usage Card**: New dedicated view showing daily costs, input/output token counts, and detailed per-model usage breakdown
- **Provider Icon**: New Bedrock provider icon with AWS orange theme for easy identification

### Improved
- **AWS SSO Authentication**: Full support for AWS SSO profile-based authentication using `SSOAWSCredentialIdentityResolver`, making it easy to use your existing AWS profiles
- **Cross-Region Inference**: Properly handles regional prefixes (us., eu., etc.) in model IDs for accurate pricing across regions
- **Model Pricing**: Added Claude Haiku 4.5 model pricing for accurate cost calculations

### Fixed
- **CloudWatch Period Calculation**: Fixed period calculation to be multiples of 60 seconds as required by CloudWatch API
- **CloudWatch Filters**: Removed problematic filters that could cause incomplete usage data

### Technical
- Implemented `BedrockUsageProbe` with CloudWatch metrics integration
- Added `SSOAWSCredentialIdentityResolver` for profile-based SSO credential resolution
- Created `BedrockUsageCard` SwiftUI view with cost and token breakdown display
- Extended visual identity system with Bedrock-specific colors and styling
- Added pricing normalization for cross-region inference model ID prefixes
- Bundled pricing data for Claude Haiku 4.5 model

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
  So these nodes are dynamically allocated, right
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

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.4.43...HEAD
[0.4.43]: https://github.com/tddworks/ClaudeBar/compare/v0.4.42...v0.4.43
[0.4.42]: https://github.com/tddworks/ClaudeBar/compare/v0.4.41...v0.4.42
[0.4.41]: https://github.com/tddworks/ClaudeBar/compare/v0.4.40...v0.4.41
[0.4.40]: https://github.com/tddworks/ClaudeBar/compare/v0.4.38...v0.4.40
[0.4.38]: https://github.com/tddworks/ClaudeBar/compare/v0.4.37...v0.4.38
[0.4.28]: https://github.com/tddworks/ClaudeBar/compare/v0.4.27...v0.4.28
[0.4.26]: https://github.com/tddworks/ClaudeBar/compare/v0.4.2...v0.4.26
[0.4.2]: https://github.com/tddworks/ClaudeBar/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/tddworks/ClaudeBar/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/tddworks/ClaudeBar/compare/v0.3.15...v0.4.0
[0.3.15]: https://github.com/tddworks/ClaudeBar/compare/v0.3.12...v0.3.15
[0.3.12]: https://github.com/tddworks/ClaudeBar/compare/v0.3.6...v0.3.12
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
