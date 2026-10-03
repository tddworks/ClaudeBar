# Bug Report: `tuist build` / `tuist test` fail with "Unexpected duplicate tasks" when using cached binaries

## Environment

- **Tuist version**: 4.153.1 (brew cask latest)
- **Xcode version**: 26.2 (Build 17C52)
- **macOS version**: 26.3 (25D125) on CI (`macos-26` runner)
- **Platform**: macOS arm64

## Description

`tuist build` and `tuist test` fail with "Unexpected duplicate tasks" when Tuist uses cached binaries for external dependencies. The same project builds and tests successfully when using `tuist generate` + `xcodebuild` directly.

The error occurs during `xcodebuild build -scheme AcceptanceTests` (or any scheme) when Tuist injects cached dependency binaries into the project, producing a dependency graph with duplicate build tasks.

## Reproduction

### Fails (Tuist caching involved)

```bash
tuist install
tuist build     # ← fails with "Unexpected duplicate tasks"
tuist test      # ← also fails
```

### Works (direct xcodebuild, no Tuist caching)

```bash
tuist install
tuist generate
xcodebuild build -scheme ClaudeBar-Workspace -workspace ClaudeBar.xcworkspace -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme ClaudeBar-Workspace -workspace ClaudeBar.xcworkspace -destination 'platform=macOS,arch=arm64'
```

## Error Output

```
Building scheme AcceptanceTests
note: Building targets in dependency order
note: Target dependency graph (87 targets)
error: Unexpected duplicate tasks
error: Unexpected duplicate tasks
** BUILD FAILED **
```

The error provides no detail about which tasks are duplicated.

## Key Observations

1. **Cache-dependent**: The failure only occurs when Tuist uses cached binaries. With `tuist generate` + `xcodebuild`, the project builds and tests without issue.

2. **Target count differs**: When Tuist injects cached binaries, the dependency graph shows 87 targets. When building directly via `xcodebuild` on a `tuist generate`-d project, xcodebuild manages its own dependency resolution without duplicates.

3. **Intermittent on CI**: Passes when Tuist's remote cache is warm (cache hit = pre-built binaries injected cleanly), fails when cache state changes (partial cache, stale entries, or different caching decisions).

4. **Not code-dependent**: Tested on multiple commits — the same code passes with `tuist generate` + `xcodebuild` but fails with `tuist build`.

## Workaround

Replace `tuist build` / `tuist test` with explicit `tuist generate` + `xcodebuild`:

```yaml
# Before (broken with cached binaries)
- run: tuist install
- run: tuist build
- run: tuist test --result-bundle-path TestResults.xcresult -- -enableCodeCoverage YES

# After (working)
- run: tuist install
- run: tuist generate
- run: xcodebuild build -scheme ClaudeBar-Workspace -workspace ClaudeBar.xcworkspace -destination 'platform=macOS,arch=arm64'
- run: |
    xcodebuild test \
      -scheme ClaudeBar-Workspace \
      -workspace ClaudeBar.xcworkspace \
      -destination 'platform=macOS,arch=arm64' \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults.xcresult
```

## Project Details

- Multi-target workspace: Domain, Infrastructure, App (ClaudeBar) + 3 test targets
- 86-87 targets in dependency graph (including external deps)
- External dependencies: AWS SDK, Sparkle, Mockable, SwiftTerm, SweetCookieKit, opentelemetry-swift
- Uses `@Mockable` macro for protocol mocking
- Uses `-skipMacroValidation` on CI
