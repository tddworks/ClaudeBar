# AGENTS.md

Rules for AI coding agents (Claude Code, Codex, Cursor, …) in this repo. This is the only agent-instructions file; there is no `CLAUDE.md`. Everything else is one link away: [docs index](docs/README.md) · [architecture](docs/architecture/ARCHITECTURE.md) · [contributing](CONTRIBUTING.md) · [docs design](docs/documentation-design/README.md).

ClaudeBar is a macOS menu bar app that shows AI coding quotas. It reads them from CLIs, APIs and local files for 27 built-in providers, plus user extensions from `~/.claudebar/extensions/`. The code is moving from three layers to modules ([MODULAR_DESIGN.md](docs/architecture/MODULAR_DESIGN.md)). Every built-in provider is a JSON definition in `Modules/Providers/Resources/Providers/`, found by `ProviderCatalog.detect()` (no Swift lists one) and run by one generic `Provider` on one shared `Engine`; what one needs that the engine can't say yet becomes a general rule in `DataSources`.

## Build & test

```bash
tuist install && tuist generate          # generated *.xcodeproj / *.xcworkspace are git-ignored
tuist test                               # every target: module tests, DomainTests, InfrastructureTests, AppTests, AcceptanceTests
tuist test Providers                     # one scheme (Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:DomainTests   # bypasses Tuist's result cache
swift test                               # the modules alone, from the root Package.swift
```

- `tuist test` caches results; use `xcodebuild test` when you need a test to really run.
- SourceKit "No such module" errors in the editor are expected; modules resolve at build time.
- The modules are `ClaudeBarKit`, the root `Package.swift`, which takes every file in a module's `Sources/`. The app and its layers are targets in `App/Project.swift`, with `**` globs; the schemes are in `Workspace.swift`. New subfolders are picked up without edits.
- Tuist 4.209 or later: the modules' tests reach `tuist test` through `includeLocalPackageTestTargets` in `Tuist/Package.swift`, and 4.209 is the first release that lets them use products from other packages (Mockable).
- `swift test` builds SwiftTerm's Metal shader, which needs Xcode's Metal Toolchain once (`xcodebuild -downloadComponent MetalToolchain`); the Tuist build leaves the shader out.

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
- **Themes** implement `AppThemeProvider` and register in `ThemeRegistry` → [themes design](docs/features/themes/design.md). Card backgrounds use `theme.cardGradient` / `theme.glassBorder`.
- The design is five documents read in order, journeys first: [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) maps them.

## Design docs are the source of truth

The design leads; code follows it. Before any change, in this order:

1. **Read the design, in order** ([the map](docs/architecture/ARCHITECTURE.md)): the person and the moment ([USER_JOURNEYS.md](docs/architecture/USER_JOURNEYS.md)), the words and each law's one owner ([CANONICAL_MODEL.md](docs/architecture/CANONICAL_MODEL.md)), the pieces and flows ([TARGET_ARCHITECTURE.md](docs/architecture/TARGET_ARCHITECTURE.md)), then the feature's or provider's own `design.md`.
2. **Place the change in it.** Which node owns it? Is it the product's lifecycle, or another question (a **capability**: declared in the definition, reached through a handle that is `nil` when not declared, never a flag or a provider's name)? Does it follow something the Monitor does (an extension point, never an edit to the Monitor)?
3. **Write the design change first** when the docs don't say it or say otherwise: the tree, the law and its owner, the pieces table. Code that disagrees with the docs is behind; never quietly bend the design to match the code.
4. **Ask the person to confirm the design** (the doc change, a diagram, the laws and owners) before writing code. No implementation until they approve.
5. **Implement to the doc.** SRP: a type changes for one reason (`Provider` only when the lifecycle does). OCP: a new provider, CLI or policy is data or a new case, never an edit to a neighbour. Views render and tell; they never compare, count, inspect folders or read quotas to decide.
6. **Ship the docs with the code**: status lines, build truth, laws.

UI changes come with a mockup in `design-concept/<feature>/` first, and, once built, screenshots of the real UI on mock data (`scripts/demo-screenshots.sh`), never real names, emails or usage.

## TDD is the default

- Write the failing test first. Swift Testing (`@Suite`, `@Test`, `#expect`) with Mockable (`given(mock).method().willReturn(…)`).
- **Chicago school**: assert on resulting state and return values; stub dependencies, don't `verify()` calls.
- **Name a test for the behaviour it guards**: `` `should <outcome> [when <situation>]` `` in the person's words, never a method, type or mechanism verb. Rename an old test when you change its file; don't sweep → [Naming tests](.claude/skills/implement-feature/references/tdd-patterns.md#naming-tests).
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
- AppTests run inside the ClaudeBar app; launched that way it starts nothing (`LaunchMode.testHost` → an empty `TestHostApp`), so tests never ask for the Keychain or read real usage. Keep new startup work in `ClaudeBarApp.init()`, never in `ClaudeBarMain`
- `docs/appcast.xml` is Sparkle's live update feed URL. Never move or hand-edit it

## Changes that touch docs

- User-visible change → one line under `## [Unreleased]` in `CHANGELOG.md`, under its one heading (`Removed` → `Changed` → `Fixed` → `Added`): the effect in the user's words, ≤300 chars, absolute issue/PR link, and `→ [docs](…)` on `Added`/`Changed` (it's shown in Sparkle's update dialog).
- Provider behaviour or probe research → that provider's `docs/providers/<id>/README.md` (users) or `design.md` (contributors).
- Which file for which change: [update rules](docs/documentation-design/README.md#update-rules). Run `python3 scripts/gen-docs.py && python3 scripts/check-docs.py --strict` before pushing.

## When you are…

- adding a provider → `add-provider` skill
- adding a feature → `implement-feature` skill (all four start with *Design docs are the source of truth* above)
- fixing a bug → `fix-bug` skill
- improving existing behaviour → `improvement` skill
- releasing or debugging CI → `github-actions` skill, [docs/release/](docs/release/RELEASE_SETUP.md)
