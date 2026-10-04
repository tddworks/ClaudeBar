---
name: fix-bug
description: |
  Guide for fixing bugs in ClaudeBar following Chicago School TDD and rich domain design. Use this skill when:
  (1) User reports a bug or unexpected behavior
  (2) Fixing a defect in existing functionality
  (3) User asks "fix this bug" or "this doesn't work correctly"
  (4) Correcting behavior that violates the user's mental model
---

# Fix Bug in ClaudeBar

Fix bugs using Chicago School TDD, root cause analysis, and rich domain design.

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. REPRODUCE & UNDERSTAND                                   │
├─────────────────────────────────────────────────────────────┤
│  • Reproduce the bug                                         │
│  • Identify expected vs actual behavior                      │
│  • Locate the root cause in code                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  2. WRITE FAILING TEST (Red)                                 │
├─────────────────────────────────────────────────────────────┤
│  • Write test that exposes the bug                           │
│  • Test should FAIL before fix                               │
│  • Test should verify CORRECT behavior                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  3. FIX & VERIFY (Green)                                     │
├─────────────────────────────────────────────────────────────┤
│  • Implement minimal fix                                     │
│  • Test now PASSES                                           │
│  • All existing tests still pass                             │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Reproduce & Understand

### Identify the Bug

1. **Reproduce**: Follow exact steps to trigger the bug
2. **Expected**: What SHOULD happen (user's mental model)
3. **Actual**: What IS happening (current behavior)
4. **Root cause**: WHY it's happening (code analysis)

### Locate in Architecture

> **Reference:** [MODULAR_DESIGN.md](../../../docs/architecture/MODULAR_DESIGN.md) (modules) ·
> [TARGET_ARCHITECTURE.md](../../../docs/architecture/TARGET_ARCHITECTURE.md) (how a provider runs) ·
> [ARCHITECTURE.md](../../../docs/architecture/ARCHITECTURE.md) (the app layers)

The code is mid-migration from three layers to modules. Find which side the
behaviour lives on before you change it:

| Where | Holds | Tests |
|---|---|---|
| `Modules/Providers/Resources/Providers/<id>.json` (+ `.js`) | every built-in provider: where the key is, how to fetch, how to read | `Modules/Providers/Tests/` (golden tests over `StubbedProvider` / `ClaudeHarness`) |
| `Modules/Providers/Sources` | `Provider` (the one lifecycle: refresh, fallback chain, accounts), `ProviderDefinition`, `AddedAccounts`, settings and account contracts | `Modules/Providers/Tests/` |
| `Modules/DataSources/Sources` | `DataSource` and its workers: credential lookups and refreshes; HTTP, steps, JSON-RPC, terminal, command, file, directory, local-server and CloudWatch fetches; JSON / text / script mapping; the process runners | `Modules/DataSources/Tests/` |
| `Modules/Quotas/Sources` | the usage model: `UsageSnapshot`, `UsageQuota`, `UsageError`, plans and costs (interim shapes, see each type's `- Note:`) | the tests of the module that uses it |
| `Sources/Domain` | `QuotaMonitor`, extension providers, Notify!, sessions, Usage History | `Tests/DomainTests/` |
| `Sources/Infrastructure` | storage, notifications, hooks, the local-log analyzers behind Usage History | `Tests/InfrastructureTests/` |
| `Sources/App` | SwiftUI views reading the domain directly | `Tests/AppTests/`, `Tests/AcceptanceTests/` |

A bug in a migrated provider is fixed in its JSON, or generically in
`DataSources`, never with vendor-named Swift. Modules never `import Domain`.

### Domain Invariants

Check if the bug violates domain invariants that should be maintained:

```swift
// Example: QuotaMonitor should maintain selection invariants
// - selectedProviderId should always point to an enabled provider
// - Domain should be self-validating (no external "ensure" calls needed)
```

## Phase 2: Write Failing Test (Red)

### Chicago School TDD

We follow **Chicago School TDD** (state-based testing):
- Test **state changes** and **return values**, not interactions
- Focus on the "what" (observable outcomes), not the "how" (method calls)
- Mocks stub dependencies to return data, not to verify calls
- No `verify()` calls - assert on resulting state instead

### Test Pattern

Test the CORRECT behavior, not the bug:

```swift
@MainActor
@Suite
struct {Component}Tests {

    @Test func `{describes correct behavior}`() async throws {
        // Given - the response that triggers the bug, captured from the real CLI/API
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":10080}}}}"#)

        // When - the real definition reads it
        let usage = try await stub.make("codex").refresh()

        // Then - assert EXPECTED behavior (will FAIL before fix)
        #expect(usage.quota(for: .session)?.windowDuration == 7 * 86400)  // the window the provider stated
    }
}
```

### Test Location

The test goes beside the code it pins (the table in Phase 1). For a migrated
provider, add the captured response to its golden tests in
`Modules/Providers/Tests/`; for a generic worker, to `Modules/DataSources/Tests/`.

### Run Test (Should FAIL)

```bash
tuist test Providers         # one module's tests (schemes: Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
tuist test                     # everything
# tuist caches results; to force a re-run of one suite:
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:ProvidersTests/ClaudeAPITests
```

## Phase 3: Fix & Verify (Green)

### Fix Guidelines

1. **Minimal change**: Fix only what's broken
2. **Domain first**: Prefer fixing in domain layer when possible
3. **Maintain invariants**: Domain should be self-validating
4. **No over-engineering**: Don't refactor unrelated code

### Domain Design Principles

When fixing domain bugs, ensure:

```swift
// 1. Domain maintains its own invariants
public init(...) {
    // Validate on construction
    selectFirstEnabledIfNeeded()  // Called internally, not externally
}

// 2. Public API hides implementation details
public func setProviderEnabled(_ id: String, enabled: Bool) {
    provider.isEnabled = enabled
    if !enabled {
        selectFirstEnabledIfNeeded()  // Private - called automatically
    }
}

// 3. Private methods for internal invariant maintenance
private func selectFirstEnabledIfNeeded() { ... }
```

### Verify Fix

Run the same suite again (it should PASS now), then `tuist test` for every
target.

## Checklist

- [ ] Bug reproduced and understood
- [ ] Root cause identified in code
- [ ] Failing test written (exposes bug)
- [ ] Test FAILS before fix
- [ ] Minimal fix implemented
- [ ] Test PASSES after fix
- [ ] All existing tests still pass
- [ ] Domain invariants maintained (if applicable)
- [ ] CHANGELOG updated with fix description