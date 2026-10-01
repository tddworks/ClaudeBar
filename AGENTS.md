# AGENTS.md

Rules for AI coding agents (Claude Code, Codex, Cursor, …) in this repo. This is the only agent-instructions file; there is no `CLAUDE.md`. Everything else is one link away: [docs index](docs/README.md) · [architecture](docs/architecture/ARCHITECTURE.md) · [contributing](CONTRIBUTING.md) · [docs design](docs/documentation-design/README.md).

ClaudeBar is a macOS menu bar app that shows AI coding quotas. It reads them from CLIs, APIs and local files through one probe per provider (20 built in, one folder each in `Sources/Domain/Provider/`, registered in `ClaudeBarApp.init()`), plus user extensions from `~/.claudebar/extensions/`.

## Build & test

```bash
tuist install && tuist generate          # generated *.xcodeproj / *.xcworkspace are git-ignored
tuist test                               # DomainTests, InfrastructureTests, AppTests, AcceptanceTests
tuist test InfrastructureTests           # one target
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:DomainTests   # bypasses Tuist's result cache
```

- `tuist test` caches results; use `xcodebuild test` when you need a test to really run.
- SourceKit "No such module" errors in the editor are expected; modules resolve at build time.
- Sources use `**` globs in `Project.swift`, so new subfolders are picked up without edits.

## Architecture

| Layer | Location | Holds |
|---|---|---|
| Domain | `Sources/Domain/` | Rich models, `QuotaMonitor`, repository protocols. No I/O |
| Infrastructure | `Sources/Infrastructure/` | Probes, storage, network, adapters |
| App | `Sources/App/` | SwiftUI views that read the domain directly |

- **`QuotaMonitor` is the single source of truth** for provider state. No ViewModel or AppState layer; views consume the domain.
- **Settings follow ISP**: providers with their own config take a sub-protocol of `ProviderSettingsRepository` (read the provider's initializer to see which). All settings persist through `JSONSettingsRepository` to `~/.claudebar/settings.json` → [docs/settings.md](docs/settings.md).
- **Notify! and session hooks are destinations, not providers**: they get standalone repositories beside `HookSettingsRepository`, never under `ProviderSettingsRepository` → [features/notify/design.md](docs/features/notify/design.md).
- **Themes** implement `AppThemeProvider` and register in `ThemeRegistry` → [THEME_DESIGN.md](docs/architecture/THEME_DESIGN.md). Card backgrounds use `theme.cardGradient` / `theme.glassBorder`.
- Details and data flow: [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).

## TDD is the default

- Write the failing test first. Swift Testing (`@Suite`, `@Test`, `#expect`) with Mockable (`given(mock).method().willReturn(…)`).
- **Chicago school**: assert on resulting state and return values; stub dependencies, don't `verify()` calls.
- Protocols that cross a boundary are `@Mockable` so tests never touch a real CLI, network or Keychain.

## Logging

- Use `AppLog.<category>` (`monitor`, `providers`, `probes`, `network`, `credentials`, `ui`, `notifications`, `updates`). `debug` goes to OSLog only; `info` and above also go to `~/Library/Logs/ClaudeBar/ClaudeBar.log`.
- **Never log a token, key, cookie or credential**: the file log has no privacy redaction. Log that something happened, not its value.
- Where users find logs and what errors mean: [docs/troubleshooting.md](docs/troubleshooting.md).

## Gotchas

- Probes run CLIs in a dedicated working directory so folder-trust prompts don't block them → [providers/claude/design.md](docs/providers/claude/design.md)
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
