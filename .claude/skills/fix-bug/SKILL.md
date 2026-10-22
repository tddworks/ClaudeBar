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
2. **Expected**: What SHOULD happen (the person's mental model — USER_JOURNEYS)
3. **Actual**: What IS happening (current behavior)
4. **Root cause**: WHY it's happening (code analysis)

For a provider that shows the wrong thing or fails:
- **The log**: `~/Library/Logs/ClaudeBar/ClaudeBar.log` (`info` and above) — which data source answered, which step failed (lookup · fetch · mapping); `debug` goes to OSLog only ([troubleshooting](../../../docs/troubleshooting.md)).
- **The failed step**: `account.lastFailedStep` and `lastError` say whether the key, the request or the reading broke — fix that piece.
- **The real response**: capture the CLI's or API's actual answer, **redacted** (no token, email, name or real usage), as the test's fixture. Never log a token, key or cookie while investigating.

### Find the law it breaks

Read the design in order — USER_JOURNEYS, CANONICAL_MODEL, TARGET_ARCHITECTURE,
then the feature's or provider's `design.md`. The design docs are the source of truth ([AGENTS.md](../../../AGENTS.md#design-docs-are-the-source-of-truth)).
A bug is usually a law in [CANONICAL_MODEL.md](../../../docs/architecture/CANONICAL_MODEL.md) §5 (or a feature's
`design.md`) that the code breaks: find the law and its **one owner**, and fix it there, not
at a call site. If the right fix changes a law or moves it to another owner, that is a
design change: update the doc and ask the user to confirm before fixing. If no law covers
it, propose the law first.

### Think how the domain should be

A bug is often a shape that let it happen: a rule a view could call and decide
for itself, two lifecycles in one class whose optionals disagree, a `String`
where a type would have refused the bad value, a boundary that guessed the
other side's format. Before fixing, ask how the domain should be, from the
person's problem, and ask the seven questions of the types the bug touches
→ [domain-shape.md](../implement-feature/references/domain-shape.md). Fix the
shape when it is the cause, in the same change, test first; a new aggregate or
a moved owner is a design change, confirmed first. A screen that contradicts
itself ("On track" beside "Runs out") is usually one law with two owners: fix it
by giving the law one owner, not by adjusting one copy.

### Locate in Architecture

> **Reference:** [MODULAR_DESIGN.md](../../../docs/architecture/MODULAR_DESIGN.md) (modules) ·
> [TARGET_ARCHITECTURE.md](../../../docs/architecture/TARGET_ARCHITECTURE.md) (how a provider runs) ·
> [ARCHITECTURE.md](../../../docs/architecture/ARCHITECTURE.md) (the app layers)

Find which module the behaviour lives in before you change it: the table in
[implement-feature → Architecture](../implement-feature/SKILL.md#architecture) is the
one map (where each thing lives, and where its tests go).

A bug or improvement in a provider is made in its JSON (or its mapping
script), or generically in `DataSources` — never with vendor-named Swift, and
never with a line in `ClaudeBarApp` that names it (providers are found by
`ProviderCatalog.detect()`). Modules never `import Domain`.

### Domain Invariants

Check if the bug violates domain invariants that should be maintained:

```swift
// Example: QuotaMonitor should maintain selection invariants
// - selectedProviderId should always point to an enabled provider
// - Domain should be self-validating (no external "ensure" calls needed)
```

## Phase 2: Write Failing Test (Red)

### Chicago School TDD

Name each test `should <outcome> [when <situation>]`, in the person's words, never a method, type or mechanism verb → [Naming tests](../implement-feature/references/tdd-patterns.md#naming-tests).

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

    @Test func `should {correct outcome} when {the situation that showed the bug}`() async throws {
        // Given - the response that triggers the bug, captured from the real CLI/API
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":10080}}}}"#)

        // When - the real definition reads it
        let usage = try await stub.make("codex").refreshPlain()

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
tuist test Providers         # one module's tests while working (schemes: Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
# tuist caches results; one suite for real, and the final check of everything:
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:ProvidersTests/ClaudeAPITests
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace -destination 'platform=macOS,arch=arm64'
```

## Phase 3: Fix & Verify (Green)

### Fix Guidelines

1. **Minimal change**: Fix only what's broken
2. **At the law's owner**: fix the one type that owns the rule (CANONICAL §5), not a call site or a view
3. **A provider is data**: its JSON or script, or a generic rule in `DataSources` that every definition gains — never a branch on a provider's id
4. **Maintain invariants**: the owner stays self-validating — tell, don't ask
5. **No over-engineering**: Don't refactor unrelated code

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

Run the same suite again (it should PASS now), then the full `xcodebuild test`
(`tuist test` skips cached targets). Then the docs in the same change: a
provider's `README.md` Gotchas when the person can hit it, its `design.md`
when the reading changed, and the CHANGELOG line.

## Checklist

- [ ] Bug reproduced and understood
- [ ] Root cause identified in code
- [ ] Domain thought through: is the bug a shape the [seven questions](../implement-feature/references/domain-shape.md) would have refused? Fixed there if so
- [ ] Failing test written (exposes bug)
- [ ] Test FAILS before fix
- [ ] Minimal fix implemented
- [ ] Test PASSES after fix
- [ ] All existing tests still pass
- [ ] Domain invariants maintained (if applicable)
- [ ] Full `xcodebuild test` green
- [ ] Docs updated where the person or a contributor would look (provider README / design.md)
- [ ] One line under `## [Unreleased]` in `CHANGELOG.md`, under its heading (`Fixed` / `Changed`): the effect in the person's words, ≤300 characters, an absolute issue or PR link