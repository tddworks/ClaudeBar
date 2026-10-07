# AGENTS.md

Rules for AI coding agents (Claude Code, Codex, Cursor, …) in this repo. This is the only agent-instructions file; there is no `CLAUDE.md`. Everything else is one link away: [docs index](docs/README.md) · [architecture](docs/architecture/ARCHITECTURE.md) · [contributing](CONTRIBUTING.md) · [docs design](docs/documentation-design/README.md).

ClaudeBar is a macOS menu bar app that shows AI coding quotas. It reads them from CLIs, APIs and local files for 27 built-in providers, plus user extensions from `~/.claudebar/extensions/`. Everything but the UI is a Kotlin SDK, `ClaudeBarKit/`; the UI is SwiftUI ([MODULAR_DESIGN.md](docs/architecture/MODULAR_DESIGN.md)). Every built-in provider is a JSON definition in `ClaudeBarKit/definitions/`, found by `ProviderCatalog.detect()` (no Swift lists one) and run by one generic `Provider` on one shared `Engine`; what one needs that the engine can't say yet becomes a general rule in `datasources`.

## Build & test

```bash
./scripts/build-kotlin.sh                # ClaudeBarKit, the Kotlin SDK (needs JDK 21); rerun after editing Kotlin
tuist install && tuist generate          # generated *.xcodeproj / *.xcworkspace are git-ignored
(cd ClaudeBarKit && ./gradlew jvmTest macosArm64Test)   # everything but the UI: JUnit, plus the native suite
tuist test                               # AppTests: the SwiftUI app's own page state and views
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar \
  -destination 'platform=macOS,arch=arm64'   # bypasses Tuist's result cache
```

- `tuist test` caches results; use `xcodebuild test` when you need a test to really run.
- SourceKit "No such module" errors in the editor are expected; modules resolve at build time.
- Sources use `**` globs in `Project.swift`, so new subfolders are picked up without edits.

## Architecture

| Where | Holds |
|---|---|
| `ClaudeBarKit/` | **everything but the UI**, one Kotlin Multiplatform SDK (SKIE framework), a package per context: `quotas`, `datasources`, `providers`, `monitoring`, `alerting`, `activity`, `leaderboard`, `storage`, `diagnostics`, `kit` (`ClaudeBarCore.start`, the composition root). `definitions/<id>.json` are the built-in providers. JUnit-tested → [MODULAR_DESIGN](docs/architecture/MODULAR_DESIGN.md) |
| `Modules/Kit` | the Swift face of ClaudeBarKit, the only target that links the framework: Sendable lines, `Date`/`Decimal`/`Int` views, `shape` enums, `KitObservation`, `Kit.shared` |
| `Sources/App` | SwiftUI and AppKit: views, the drivers that push state to the menu bar, notch and Touch Bar, and page state (`PageState/`) |

- **Kotlin never calls Swift**, and no Kotlin names a vendor or uses `Probe`: a provider is data, and what it needs becomes a generic rule in `datasources` → [TARGET_ARCHITECTURE.md](docs/architecture/TARGET_ARCHITECTURE.md). The package rules are `ArchitectureTest`'s.
- **Only `Modules/Kit` names the bridge** (`onEnum`, `KotlinLong`, `companion`, `…Seconds`): views read Swift types and call commands; a command that can fail answers with an `Outcome`, read with `value(of:)` → [MODULAR_DESIGN §5](docs/architecture/MODULAR_DESIGN.md#5--the-ui-bridge).

- **`QuotaMonitor` is the single source of truth** for provider state (`Kit.shared.monitor`). No ViewModel or AppState layer; views read the kit, and every `body` calls `KitObservation.track()` so the kit's one change signal re-renders it.
- **Settings**: a provider's settings are its definition's `settings`, read with the generic `value`/`dataSourceKind`/`isOn` of Kotlin's `ProviderSettingsRepository`; a value an old card saved elsewhere is read through the compatibility tables in `JsonProviderSettings` and `ProviderVault`. Everything persists to `~/.claudebar/settings.json` through `storage`'s `SettingsFile`; Swift's `JSONSettingsRepository` keeps only the app's own settings → [docs/settings.md](docs/settings.md).
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

- Write the failing test first: JUnit for anything in `ClaudeBarKit/` (fakes, no mocking framework), Swift Testing (`@Suite`, `@Test`, `#expect`) for the App's page state.
- **Chicago school**: assert on resulting state and return values; stub dependencies, don't `verify()` calls.
- **Name a test for the behaviour it guards**: `` `should <outcome> [when <situation>]` `` in the person's words, never a method, type or mechanism verb. Rename an old test when you change its file; don't sweep → [Naming tests](.claude/skills/implement-feature/references/tdd-patterns.md#naming-tests).
- Ports that cross a boundary are Kotlin interfaces with fakes in `jvmTest`, so tests never touch a real CLI, network or Keychain. An App test that needs providers starts its own kit over a temporary home (`Tests/AppTests/Support/TestKit.swift`).

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
