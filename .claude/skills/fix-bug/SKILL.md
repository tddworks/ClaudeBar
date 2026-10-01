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

> **Reference:** [docs/architecture/ARCHITECTURE.md](../../../docs/architecture/ARCHITECTURE.md)

| Layer | Location | What to look for |
|-------|----------|------------------|
| **Domain** | `Sources/Domain/` | Incorrect business logic, missing invariants |
| **Infrastructure** | `Sources/Infrastructure/` | Parsing errors, CLI/API issues |
| **App** | `Sources/App/` | View state issues, binding problems |

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
@Suite
struct {Component}Tests {

    @Test func `{describes correct behavior}`() {
        // Given - setup that triggers the bug scenario
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
        claude.isEnabled = false  // Bug trigger condition

        // When - action that should work correctly
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude, codex]))

        // Then - assert EXPECTED behavior (will FAIL before fix)
        #expect(monitor.selectedProviderId == "codex")  // Not "claude"
    }
}
```

### Test Location

| Bug Location | Test Location |
|--------------|---------------|
| `Sources/Domain/Monitor/` | `Tests/DomainTests/Monitor/` |
| `Sources/Domain/Provider/` | `Tests/DomainTests/Provider/` |
| `Sources/Infrastructure/CLI/` | `Tests/InfrastructureTests/CLI/` |

### Run Test (Should FAIL)

```bash
swift test --filter "{TestSuiteName}"
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

```bash
# Run the specific test (should PASS now)
swift test --filter "{TestSuiteName}"

# Run ALL tests to ensure no regressions
swift test
```

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