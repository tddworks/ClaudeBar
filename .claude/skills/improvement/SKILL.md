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
| A new report card over usage history | add-report |

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  0. CHECK THE DESIGN (docs are the source of truth)          │
├─────────────────────────────────────────────────────────────┤
│  • Read USER_JOURNEYS, CANONICAL, TARGET, design.md          │
│  • Think the domain: how should it be? (domain-shape.md)     │
│  • Does the improvement change a law, an owner, a word?      │
│  • If so: write it into the docs, ask the user to confirm    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ (design confirmed, or unchanged)
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

## Phase 0: Check the design

The design docs are the source of truth ([AGENTS.md](../../../AGENTS.md#design-docs-are-the-source-of-truth)).
Read the design in order — [USER_JOURNEYS.md](../../../docs/architecture/USER_JOURNEYS.md),
[CANONICAL_MODEL.md](../../../docs/architecture/CANONICAL_MODEL.md), [TARGET_ARCHITECTURE.md](../../../docs/architecture/TARGET_ARCHITECTURE.md), then the
feature's `design.md`. An improvement that only makes the code match the docs needs no
approval. One that changes a law, its owner, a word the screen prints, or adds a piece is a
design change: write it into the docs and ask the user to confirm before coding.

**Think the domain first.** Before changing code, ask how the domain should be,
from the person's problem rather than the class at hand. Ask the seven questions of
the types the improvement touches (would the person say it, does the thing
decide about itself and alone, can you see every state, is it as small as it
can be, is what differs data, does it change for one reason, is each concern on
its own side) and refine them in the same change → [domain-shape.md](../implement-feature/references/domain-shape.md).
An improvement is the usual moment to fit a type to its shape; a new aggregate
or a moved owner is a design change, confirmed first.

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

**Test approach**: a mockup in `design-concept/<feature>/` first for a visible change,
then the real UI on mock data (`scripts/demo-screenshots.sh`) — never real names,
emails or usage. Views render and tell; a rule they need lives in the domain.

### 2. Domain Improvements

Enhance a rule on the type that owns it (CANONICAL §5) — tell, don't ask:

```
Examples:
- A status the view used to work out moves onto its owner
- A better status calculation
- Better encapsulation of an invariant
```

**Never** a new field on `UsageSnapshot`: the kernel is shrinking toward `Usage`
(CANONICAL §6). Put the rule on the value or aggregate that owns it.

**Test approach**: State-based tests on the owner

```swift
@Test func `should be critical when a tenth is left`() {
    let quota = UsageQuota(percentRemaining: 10, quotaType: .session, providerId: "claude")
    #expect(quota.status == .critical)
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

Name each test `should <outcome> [when <situation>]`, in the person's words, never a method, type or mechanism verb → [Naming tests](../implement-feature/references/tdd-patterns.md#naming-tests).

### Write Test for Improved Behavior

```swift
@Suite
struct {Component}Tests {

    @Test func `should {improved outcome} [when {situation}]`() {
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
tuist test Providers         # one module's tests while working (schemes: Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
# tuist caches results; one suite for real, and the final check of everything:
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:ProvidersTests/ClaudeAPITests
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace -destination 'platform=macOS,arch=arm64'
```


## Architecture Reference

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

## Guidelines

### Do

- Keep changes focused and minimal
- Maintain existing behavior
- Add tests for new behavior
- Follow existing code patterns
- Add the CHANGELOG line for a change the person notices

### Don't

- Over-engineer simple improvements
- Change unrelated code
- Break existing tests
- Add features (use implement-feature)
- Skip tests for "small" changes

## Checklist

- [ ] Current behavior understood
- [ ] Domain thought through: the touched types asked [the seven questions](../implement-feature/references/domain-shape.md), refined in scope
- [ ] Improvement scope defined (minimal)
- [ ] Test for improved behavior written
- [ ] Test FAILS before implementation
- [ ] Improvement implemented
- [ ] New test PASSES
- [ ] Full `xcodebuild test` green (`tuist test` skips cached targets)
- [ ] Docs updated in the same change (feature or provider README / design.md)
- [ ] One line under `## [Unreleased]` in `CHANGELOG.md`, under its heading (`Fixed` / `Changed`): the effect in the person's words, ≤300 characters, an absolute issue or PR link, for a change the person notices
