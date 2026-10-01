# Contributing

Thanks for helping. This page covers building, testing and getting a PR merged. Agents working in the repo also read [AGENTS.md](AGENTS.md).

## Build & test

Needs macOS 15+, Xcode with Swift 6.2+, and [Tuist](https://tuist.io) (`brew install tuist`).

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

## How code is organised

Three layers: `Sources/Domain` (models, `QuotaMonitor` as the single source of truth, protocols), `Sources/Infrastructure` (probes, storage, network) and `Sources/App` (SwiftUI views that read the domain directly, no ViewModels). The why and the data flow: [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md).

## Adding a provider

Ask your agent to "add a new provider for X" to load the `add-provider` skill (`.claude/skills/add-provider/`). It walks through parsing tests → probe tests → probe → provider → registration. Read a similar provider's `docs/providers/<id>/design.md` first, and add `docs/providers/<id>/README.md` for the new one.

## Rules

- **Test first.** Chicago-school TDD with Swift Testing and `@Mockable`: assert on resulting state, not on calls. Bugs get a failing test before the fix (`fix-bug` skill).
- Follow the layering and naming in [AGENTS.md](AGENTS.md).
- **One CHANGELOG line** under `## [Unreleased]` for anything a user would notice. It is shown in Sparkle's update dialog, so write the effect in the user's words, ≤300 characters, and end with an absolute issue or PR link.

## Docs

Each fact has one home. Which file to touch for which change is in the [update rules](docs/documentation-design/README.md#update-rules). Check before pushing:

```bash
python3 scripts/gen-docs.py      # regenerate docs/README.md after changing a description
python3 scripts/check-docs.py --strict
```

## Releasing

Maintainers only: push a `vX.Y.Z` tag and GitHub Actions builds, signs, notarizes, publishes the release and updates the Sparkle appcast. Setup and secrets: [docs/release/RELEASE_SETUP.md](docs/release/RELEASE_SETUP.md).
