---
name: improvement
description: |
  Guide for making improvements to existing ClaudeBar functionality using TDD. Use this skill when:
  (1) Enhancing existing features (not adding new ones)
  (2) Improving UX, performance, or code quality
  (3) User asks "improve X", "make Y better", or "enhance Z"
  (4) Small enhancements that don't require full architecture design
  For NEW features, use implement-feature skill instead.
---

# Improve ClaudeBar Feature

Make improvements to existing functionality using TDD and rich domain design.

## When to Use This vs Other Skills

| Scenario | Skill to Use |
|----------|--------------|
| Enhance existing behavior | **improvement** (this skill) |
| Fix broken behavior | fix-bug |
| Add new feature | implement-feature |
| Add new AI provider | add-provider |

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. UNDERSTAND CURRENT STATE                                 │
├─────────────────────────────────────────────────────────────┤
│  • Read existing code                                        │
│  • Understand current behavior                               │
│  • Identify what to improve                                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  2. WRITE TEST FOR IMPROVED BEHAVIOR (Red)                   │
├─────────────────────────────────────────────────────────────┤
│  • Test describes the IMPROVED behavior                      │
│  • Test should FAIL initially                                │
│  • Keep existing tests passing                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  3. IMPLEMENT & VERIFY (Green)                               │
├─────────────────────────────────────────────────────────────┤
│  • Implement the improvement                                 │
│  • New test PASSES                                           │
│  • All existing tests still pass                             │
└─────────────────────────────────────────────────────────────┘
```

## Types of Improvements

### 1. UX Improvements

Enhance user experience without changing core logic:

```
Examples:
- Settings view scrolls on small screens
- Better loading indicators
- Improved accessibility
- Cleaner visual layout
```

**Test approach**: UI behavior tests or manual verification

### 2. Domain Improvements

Enhance domain model behavior:

```
Examples:
- Add computed property for common queries
- Improve status calculation
- Add convenience methods
- Better encapsulation
```

**Test approach**: State-based domain tests

```swift
@Test func `model provides convenient access to lowest quota`() {
    // Given
    let snapshot = UsageSnapshot(quotas: [quota1, quota2, quota3])

    // Then - new convenience property
    #expect(snapshot.lowestQuota == quota2)
}
```

### 3. Data Source Improvements

Make fetching or reading usage better: a provider's definition, or a generic
worker in `DataSources` that every definition can use:

```
Examples:
- Better error messages (a `text` mapping's error phrases, a `UsageError` hint)
- More robust reading (a new JSON mapping rule instead of a script)
- Timeouts, `cache.ttl`, a remembered rate limit
- A fallback or hand-off (`fallback`, `fallbackOn`)
```

**Test approach**: golden tests that run the real definition over stubbed
connections (`StubbedProvider`), or worker tests in `Modules/DataSources/Tests/`.
Never a vendor-named Swift type: improve the definition, or the generic piece.

### 4. Performance Improvements

Optimize existing functionality:

```
Examples:
- Reduce redundant API calls
- Lazy loading
- Parallel execution
- Caching
```

**Test approach**: Behavior tests (same results, better performance)

## TDD Pattern (Chicago School)

### Write Test for Improved Behavior

```swift
@Suite
struct {Component}Tests {

    @Test func `{describes improved behavior}`() {
        // Given - standard setup
        let component = Component(...)

        // When - action
        let result = component.improvedMethod()

        // Then - verify improved behavior
        #expect(result.hasImprovedProperty)
    }
}
```

### Keep Existing Tests

Improvements should NOT break existing behavior:

```bash
tuist test Providers         # one module's tests (schemes: Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
tuist test                     # everything
# tuist caches results; to force a re-run of one suite:
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:ProvidersTests/ClaudeAPITests
```


## Architecture Reference

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

## Guidelines

### Do

- Keep changes focused and minimal
- Maintain existing behavior
- Add tests for new behavior
- Follow existing code patterns
- Update CHANGELOG

### Don't

- Over-engineer simple improvements
- Change unrelated code
- Break existing tests
- Add features (use implement-feature)
- Skip tests for "small" changes

## Checklist

- [ ] Current behavior understood
- [ ] Improvement scope defined (minimal)
- [ ] Test for improved behavior written
- [ ] Test FAILS before implementation
- [ ] Improvement implemented
- [ ] New test PASSES
- [ ] All existing tests still pass (`tuist test`)
- [ ] CHANGELOG updated with improvement
