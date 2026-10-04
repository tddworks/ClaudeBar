# AGENTS.md

Rules for AI coding agents (Claude Code, Codex, Cursor, …) in this repo. This is the only agent-instructions file; there is no `CLAUDE.md`. Everything else is one link away: [docs index](docs/README.md) · [architecture](docs/architecture/ARCHITECTURE.md) · [contributing](CONTRIBUTING.md) · [docs design](docs/documentation-design/README.md).

ClaudeBar is a macOS menu bar app that shows AI coding quotas. It reads them from CLIs, APIs and local files for 20 built-in providers, registered in `ClaudeBarApp.init()`, plus user extensions from `~/.claudebar/extensions/`. The code is moving from three layers to modules ([MODULAR_DESIGN.md](docs/architecture/MODULAR_DESIGN.md)). Every built-in provider is a JSON definition in `Modules/Providers/Resources/Providers/`, run by one generic `Provider`; what one needs that the engine can't say yet becomes a general rule in `DataSources`.

## Build & test

```bash
tuist install && tuist generate          # generated *.xcodeproj / *.xcworkspace are git-ignored
tuist test                               # every target: module tests, DomainTests, InfrastructureTests, AppTests, AcceptanceTests
tuist test Providers                     # one scheme (Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:DomainTests   # bypasses Tuist's result cache
```

- `tuist test` caches results; use `xcodebuild test` when you need a test to really run.
- SourceKit "No such module" errors in the editor are expected; modules resolve at build time.
- Sources use `**` globs in `Project.swift`, so new subfolders are picked up without edits.

## Architecture

| Where | Holds |
|---|---|
| `Modules/Quotas` | the usage model: `UsageSnapshot`, `UsageQuota`, `UsageError` (interim shapes, each marked with its final one). Imports nothing |
| `Modules/DataSources` | `DataSource` (credential lookup → fetch → mapping) and its workers: OAuth, HTTP, JSON-RPC, CLI, JSON/text/script mapping |
| `Modules/Providers` | the one `Provider` lifecycle, `ProviderDefinition`, added accounts, settings contracts, a login's `usageHistory` and `guestPasses`; `Resources/Providers/<id>.json` |
| `Modules/AWSClients` | the AWS SDK (CloudWatch, Bedrock pricing) behind DataSources' `CloudWatchClient` and `PriceCatalog` ports; the only module that links AWS |
| `Modules/Diagnostics` | `AppLog` |
| `Sources/Domain` | `QuotaMonitor`, extension providers, Notify!, sessions. Re-exports the modules |
| `Sources/Infrastructure` | storage, notifications, hooks, Claude's guest-pass source |
| `Sources/App` | SwiftUI views that read the domain directly; the composition root |

- **Modules never `import Domain`**, and no module's Swift names a vendor or uses `Probe`: a provider is data, and what it needs becomes a generic rule in `DataSources` → [TARGET_ARCHITECTURE.md](docs/architecture/TARGET_ARCHITECTURE.md).

- **`QuotaMonitor` is the single source of truth** for provider state. No ViewModel or AppState layer; views consume the domain.
- **Settings**: a provider's settings are its definition's `settings`, read with the generic `value`/`dataSourceKind`/`isOn` of `ProviderSettingsRepository`; a value an old card saved elsewhere is read through the compatibility tables in `JSONSettingsRepository` and `ProviderVault`. All settings persist through `JSONSettingsRepository` to `~/.claudebar/settings.json` → [docs/settings.md](docs/settings.md).
- **Notify! and session hooks are destinations, not providers**: they get standalone repositories beside `HookSettingsRepository`, never under `ProviderSettingsRepository` → [features/notify/design.md](docs/features/notify/design.md).
- **Themes** implement `AppThemeProvider` and register in `ThemeRegistry` → [THEME_DESIGN.md](docs/architecture/THEME_DESIGN.md). Card backgrounds use `theme.cardGradient` / `theme.glassBorder`.
- Details and data flow: [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) (the legacy layers) and [CANONICAL_MODEL.md](docs/architecture/CANONICAL_MODEL.md) (the words).

## TDD is the default

- Write the failing test first. Swift Testing (`@Suite`, `@Test`, `#expect`) with Mockable (`given(mock).method().willReturn(…)`).
- **Chicago school**: assert on resulting state and return values; stub dependencies, don't `verify()` calls.
- Protocols that cross a boundary are `@Mockable` so tests never touch a real CLI, network or Keychain.

## Logging

- Use `AppLog.<category>` (`monitor`, `providers`, `probes`, `network`, `credentials`, `ui`, `notifications`, `updates`). `debug` goes to OSLog only; `info` and above also go to `~/Library/Logs/ClaudeBar/ClaudeBar.log`.
- **Never log a token, key, cookie or credential**: the file log has no privacy redaction. Log that something happened, not its value.
- Where users find logs and what errors mean: [docs/troubleshooting.md](docs/troubleshooting.md).

## Gotchas

- CLI fetches run in a dedicated working directory (`ClaudeBar/Probe`, a name kept because CLIs already trust it) so folder-trust prompts don't block them → [providers/claude/design.md](docs/providers/claude/design.md)
- Codex RPC: keep `resetsAt` and `windowDurationMins`; the primary window can be the weekly one → [providers/codex/design.md](docs/providers/codex/design.md)
- An empty `pgrep` result surfaces as a runner timeout, not "not found" → [providers/antigravity/design.md](docs/providers/antigravity/design.md)
- A key exported only in the user's shell profile is invisible when the app starts from Finder or at login → provider Gotchas
- Local builds are ad-hoc signed and the Keychain can refuse them; code that stores secrets needs a fallback (Notify! has one, Vercel doesn't) → [docs/settings.md](docs/settings.md), [providers/vercel-gateway](docs/providers/vercel-gateway/README.md)
- `docs/appcast.xml` is Sparkle's live update feed URL. Never move or hand-edit it

## Changes that touch docs

- User-visible change → one line under `## [Unreleased]` in `CHANGELOG.md`: the effect in the user's words, ≤300 chars, absolute issue/PR link (it's shown in Sparkle's update dialog).
- Provider behaviour or probe research → that provider's `docs/providers/<id>/README.md` (users) or `design.md` (contributors).
- Which file for which change: [update rules](docs/documentation-design/README.md#update-rules). Run `python3 scripts/gen-docs.py && python3 scripts/check-docs.py --strict` before pushing.

## When you are…

- adding a provider → `add-provider` skill
- adding a feature → `implement-feature` skill
- fixing a bug → `fix-bug` skill
- improving existing behaviour → `improvement` skill
- releasing or debugging CI → `github-actions` skill, [docs/release/](docs/release/RELEASE_SETUP.md)
