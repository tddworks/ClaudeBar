# Contributing

Thanks for helping. This page covers building, testing and getting a PR merged. Agents working in the repo also read [AGENTS.md](AGENTS.md).

## Build & test

Needs macOS 15+, Xcode with Swift 6.2+, and [Tuist](https://tuist.io) 4.209 or later (`brew install tuist`, or `brew upgrade tuist` for an older one).

```bash
git clone https://github.com/tddworks/ClaudeBar.git && cd ClaudeBar
tuist install                  # resolve dependencies
tuist generate                 # generate and open ClaudeBar.xcworkspace; ⌘R runs the app
tuist test                     # all tests (DomainTests, InfrastructureTests, AppTests, AcceptanceTests)
tuist test DomainTests         # one target
tuist build ClaudeBar -C Release
```

- `tuist test` caches results and skips targets it thinks are unchanged. To force a real run: `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace -destination 'platform=macOS,arch=arm64'`.
- Coverage: `tuist test --result-bundle-path TestResults.xcresult -- -enableCodeCoverage YES`.
- SwiftUI previews work in Xcode (`⌘⌥↩`); the project sets `ENABLE_DEBUG_DYLIB` for them.
- "No such module" errors from SourceKit in your editor are expected; modules resolve when Tuist builds.
- The modules are also a Swift package, `ClaudeBarKit`, in the root `Package.swift`: `swift test` runs their tests without Tuist. It builds SwiftTerm's Metal shader, so it needs Xcode's Metal Toolchain once (`xcodebuild -downloadComponent MetalToolchain`).

## How code is organised

Every built-in provider is a JSON definition in `Modules/Providers/Resources/Providers/`, run by one generic `Provider` and `DataSource` (`Modules/`). Around them: `Sources/Domain` (`QuotaMonitor` as the single source of truth, sessions, Notify!), `Sources/Infrastructure` (storage, notifications, hooks) and `Sources/App` (SwiftUI views that read the domain directly, no ViewModels). The design, in the order to read it: [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).

## Adding a provider

Ask your agent to "add a new provider for X" to load the `add-provider` skill (`.claude/skills/add-provider/`). It walks through captured fixtures → golden tests → the JSON definition (and a general engine rule when the definition can't say something) → registration. Read a similar provider's `docs/providers/<id>/design.md` first, and add `docs/providers/<id>/README.md` for the new one.

## Rules

- **Start from the problem.** An issue or PR says what someone was doing and what got in the way before it proposes a fix: a request for a solution hides the real need (the [XY problem](https://xyproblem.info)). The issue and PR templates ask in that order; the design follows the problem, in the design docs ([AGENTS.md](AGENTS.md#design-docs-are-the-source-of-truth)).
- **Test first.** Chicago-school TDD with Swift Testing and `@Mockable`: assert on resulting state, not on calls. Bugs get a failing test before the fix (`fix-bug` skill).
- Follow the layering and naming in [AGENTS.md](AGENTS.md).
- By opening a pull request you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), like the rest of ClaudeBar.
- **One CHANGELOG line** under `## [Unreleased]` for anything a user would notice. It is shown in Sparkle's update dialog, so write the effect in the user's words, ≤300 characters, and end with an absolute issue or PR link. `Added` and `Changed` lines also link their doc (`→ [docs](…)`), and each kind of change has one heading, in the order `Removed` → `Changed` → `Fixed` → `Added`; past minors live in [docs/changelog/](docs/changelog/).

## Docs

Each fact has one home. Which file to touch for which change is in the [update rules](docs/documentation-design/README.md#update-rules). Check before pushing:

```bash
python3 scripts/gen-docs.py      # regenerate docs/README.md after changing a description
python3 scripts/check-docs.py --strict
```

## Releasing

Maintainers only: push a `vX.Y.Z` tag and GitHub Actions builds, signs, notarizes, publishes the release and updates the Sparkle appcast. Setup and secrets: [docs/release/RELEASE_SETUP.md](docs/release/RELEASE_SETUP.md).
