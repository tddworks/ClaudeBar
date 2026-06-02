# Copilot "AI Credits" Rebranding & Monthly Card Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update ClaudeBar's GitHub Copilot integration to reflect GitHub's new "AI Credits" billing model. Rename user-facing "premium requests" / "requests" terminology to "AI credits", and change the Copilot card title to "Monthly" with a "Resets in Xd" countdown driven by the calendar (1st of next month, UTC).

**Architecture:**
- Quota type becomes `.timeLimit("Monthly")` (reuses existing 30-day `QuotaDuration` precedent; `displayName == "Monthly"`).
- Both probes compute `resetsAt` as the first instant of next month in UTC (a small new helper).
- The internal API continues to be queried, but the parsed `quotaResetDateUtc` is replaced with the computed calendar value (per user direction).
- All user-facing strings (UI labels, hints, reset text) are renamed from "premium requests" / "requests" to "AI credits". Internal storage keys and API URLs are unchanged.

**Tech Stack:** Swift 6.2, Swift Testing (where used), XCTest (legacy), SwiftUI, Tuist, TDD (Chicago School — state changes).

---

## Background

GitHub Copilot now bills usage as **AI Credits** instead of premium requests (see [usage-based billing docs](https://docs.github.com/en/copilot/concepts/billing/usage-based-billing-for-individuals)). All paid plans (Pro, Pro+, Max) get a monthly allowance measured in credits; one credit ≈ $0.01 of model spend. The previous "premium request" model is gone.

ClaudeBar currently shows Copilot as a "Session" card with strings like `"10/50 requests"`, `"CURRENT PREMIUM REQUEST USAGE"`, and `"MONTHLY PREMIUM REQUEST LIMIT"`. The card does not show a time-based reset countdown because neither probe populates `resetsAt`.

This plan renames the user-facing vocabulary and gives the card a proper "Monthly" identity with a "Resets in Xd" countdown.

---

## User Decisions (Confirmed)

1. **Quota type**: Use `QuotaType.timeLimit("Monthly")` — existing case, displayName "Monthly", duration 30 days.
2. **Reset date source**: Compute from current date (1st of next month, UTC). The internal API's `quotaResetDateUtc` is no longer used as the source of truth.
3. **Billing API endpoint**: Keep hitting `/users/{username}/settings/billing/premium_request/usage`. Only rename user-facing strings; the URL stays (GitHub has not yet deprecated it).
4. **Settings keys**: Keep `copilot.monthlyLimit`, `copilot.manualUsageValue`, etc. No JSON migration.

---

## File Structure

### New files
- `Sources/Domain/Provider/Copilot/MonthlyResetDate.swift` — pure function `nextMonthlyResetDate(referenceDate: Date = Date()) -> Date` returning the start of the next UTC month. Easy to unit-test, no dependencies.

### Modified files

**Domain / Infrastructure (probes & provider):**
- `Sources/Domain/Provider/Copilot/CopilotProvider.swift` — change `quotaType: .session` → `quotaType: .timeLimit("Monthly")` in both probes' return values (passes through; the provider itself doesn't construct the quota).
- `Sources/Infrastructure/Copilot/CopilotInternalAPIProbe.swift` — switch quota type to `.timeLimit("Monthly")`; populate `resetsAt` from `MonthlyResetDate.nextMonthlyResetDate()`; rename `resetText` strings to "AI credits".
- `Sources/Infrastructure/Copilot/CopilotUsageProbe.swift` — switch quota type to `.timeLimit("Monthly")`; populate `resetsAt`; rename `resetText` strings to "AI credits"; rename log strings.

**UI:**
- `Sources/App/Views/Settings/CopilotConfigCard.swift` — rename section labels: `"MONTHLY PREMIUM REQUEST LIMIT"` → `"MONTHLY AI CREDITS LIMIT"`, `"CURRENT PREMIUM REQUEST USAGE"` → `"CURRENT AI CREDITS USAGE"`; rename the explanatory note; rename the input hint; rename the card subtitle from `"Premium usage tracking"` → `"AI credits usage tracking"`.
- (No changes needed to `WrappedStatCard`, `QuotaCardView`, or `ProviderSectionView` — they render `quota.quotaType.displayName` which becomes "Monthly" automatically. They also display `resetTimestampDescription ?? resetText` — once `resetsAt` is set, the timestamp description ("Resets in 12d") takes over and our "X/Y credits" suffix no longer dominates the card body.)

**Tests:**
- `Tests/DomainTests/Provider/Copilot/MonthlyResetDateTests.swift` — new tests for the reset-date helper.
- `Tests/InfrastructureTests/Copilot/CopilotInternalAPIProbeTests.swift` — update existing assertions for the new quota type, `resetsAt`, and renamed strings; add coverage for "Resets in Xd" countdown surfacing.
- `Tests/InfrastructureTests/Copilot/CopilotUsageProbeTests.swift` — same.
- `Tests/DomainTests/Provider/Copilot/CopilotProviderTests.swift` — update any quota-type assertions.
- `Tests/AcceptanceTests/CopilotConfigSpec.swift` — update any user-facing string assertions and quota-type assertions.

---

## Task Decomposition

Tasks are ordered so each one leaves the tree compiling and tests green. Each task is one logical commit.

---

### Task 1: Add `MonthlyResetDate` helper + tests (TDD)

**Files:**
- Create: `Sources/Domain/Provider/Copilot/MonthlyResetDate.swift`
- Create: `Tests/DomainTests/Provider/Copilot/MonthlyResetDateTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/DomainTests/Provider/Copilot/MonthlyResetDateTests.swift`:

```swift
import Foundation
import Testing
@testable import Domain

@Suite("MonthlyResetDate")
struct MonthlyResetDateTests {

    @Test("returns first instant of next UTC month when reference is mid-month")
    func midMonth() {
        let ref = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let result = MonthlyResetDate.nextMonthlyResetDate(referenceDate: ref)
        #expect(result == ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    }

    @Test("rolls into next year from December")
    func december() {
        let ref = ISO8601DateFormatter().date(from: "2026-12-31T23:59:59Z")!
        let result = MonthlyResetDate.nextMonthlyResetDate(referenceDate: ref)
        #expect(result == ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z"))
    }

    @Test("returns start of next month when reference is exactly the boundary")
    func exactlyBoundary() {
        let ref = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
        let result = MonthlyResetDate.nextMonthlyResetDate(referenceDate: ref)
        #expect(result == ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
    }

    @Test("result is always in the future relative to reference")
    func alwaysFuture() {
        let ref = Date()
        let result = MonthlyResetDate.nextMonthlyResetDate(referenceDate: ref)
        #expect(result > ref)
    }
}
```

- [ ] **Step 2: Run tests — expect failure (symbol not found)**

```bash
tuist test DomainTests -- -only-testing:DomainTests/MonthlyResetDateTests
```

Expected: compile failure (`MonthlyResetDate` not defined).

- [ ] **Step 3: Implement `MonthlyResetDate`**

Create `Sources/Domain/Provider/Copilot/MonthlyResetDate.swift`:

```swift
import Foundation

/// Computes the next monthly reset instant for GitHub Copilot AI Credits.
/// GitHub's billing cycle rolls over at 00:00 UTC on the 1st of each month.
public enum MonthlyResetDate {
    /// Returns the start of the next UTC month relative to `referenceDate`.
    /// If `referenceDate` is exactly 00:00:00 UTC on the 1st, returns the 1st of the *next* month.
    public static func nextMonthlyResetDate(referenceDate: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let year = comps.year, let month = comps.month,
              let startOfCurrent = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfCurrent)
        else {
            return referenceDate
        }
        return nextMonth
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
tuist test DomainTests -- -only-testing:DomainTests/MonthlyResetDateTests
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Domain/Provider/Copilot/MonthlyResetDate.swift \
        Tests/DomainTests/Provider/Copilot/MonthlyResetDateTests.swift
git commit -m "feat(copilot): add MonthlyResetDate helper for UTC month rollover"
```

---

### Task 2: Update `CopilotInternalAPIProbe` — quota type, `resetsAt`, and AI credits strings

**Files:**
- Modify: `Sources/Infrastructure/Copilot/CopilotInternalAPIProbe.swift`
- Modify: `Tests/InfrastructureTests/Copilot/CopilotInternalAPIProbeTests.swift`

- [ ] **Step 1: Update existing tests first to assert the new contract**

In `Tests/InfrastructureTests/Copilot/CopilotInternalAPIProbeTests.swift`, change assertions for quota type, `resetsAt`, and `resetText`:

```swift
// Replace any assertion like:
#expect(quota.quotaType == .session)
// With:
#expect(quota.quotaType == .timeLimit("Monthly"))
#expect(quota.resetText == "0/300 AI credits")
#expect(quota.resetsAt != nil)  // populated from MonthlyResetDate
```

Rename `"premium requests"` → `"AI credits"` everywhere it appears in test assertions and reset-text expectations. There are three resetText variants in the probe to rename:
- `"No premium requests quota"` → `"No AI credits quota"`
- `"Unlimited premium requests"` → `"Unlimited AI credits"`
- `"\(used)/\(entitlement) requests"` → `"\(used)/\(entitlement) AI credits"`

Update log-message assertions to match (e.g. `"Used X/Y premium requests, ..."` → `"Used X/Y AI credits, ..."`).

Add a new test at the end of the suite:

```swift
@Test("populates resetsAt with the start of the next UTC month")
func populatesResetsAt() async throws {
    // arrange a normal entitlement response (use the existing helper that returns a populated premiumInteractions)
    let snapshot = try await probe.probe()
    let quota = try #require(snapshot.quotas.first)
    let calendar = Calendar(identifier: .gregorian)
    var utc = calendar; utc.timeZone = TimeZone(identifier: "UTC")!
    let now = Date()
    let nowComps = utc.dateComponents([.year, .month], from: now)
    let startOfCurrentMonth = try #require(utc.date(from: nowComps))
    let expected = try #require(utc.date(byAdding: .month, value: 1, to: startOfCurrentMonth))
    #expect(quota.resetsAt == expected)
}
```

(If the existing test file uses XCTest instead of Swift Testing, mirror the existing assertion style — `XCTAssertEqual` etc. The probe is the only thing changing; the test file's framework is whatever is already in use there.)

- [ ] **Step 2: Run tests — expect failure**

```bash
tuist test InfrastructureTests -- -only-testing:InfrastructureTests/CopilotInternalAPIProbeTests
```

Expected: assertions fail (quota type is still `.session`, `resetsAt` is nil, strings say "requests").

- [ ] **Step 3: Modify `CopilotInternalAPIProbe.swift`**

Three locations to update (the file has 212 lines; the construction sites are at ~lines 133, 150, 175):

```swift
// Site 1 (no premium_interactions found):
let quota = UsageQuota(
    percentRemaining: 100,
    quotaType: .timeLimit("Monthly"),
    providerId: "copilot",
    resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
    resetText: "No AI credits quota"
)

// Site 2 (unlimited premium interactions):
let quota = UsageQuota(
    percentRemaining: 100,
    quotaType: .timeLimit("Monthly"),
    providerId: "copilot",
    resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
    resetText: "Unlimited AI credits"
)

// Site 3 (normal entitlement):
let resetText = "\(used)/\(entitlement) AI credits"
let quota = UsageQuota(
    percentRemaining: percentRemaining,
    quotaType: .timeLimit("Monthly"),
    providerId: "copilot",
    resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
    resetText: resetText
)
```

Update the log line at ~171:

```swift
AppLog.probes.debug("Copilot Internal API: Used \(used)/\(entitlement) AI credits, \(Int(percentRemaining))% remaining")
```

(Optional cleanup: the comment block at the top and the "premium_interactions" filter key can stay — they describe the JSON wire format which GitHub has not yet renamed. Add a one-line note: `// GitHub's API still uses "premium_interactions" / "premium_request" in wire JSON; we surface the data as "AI credits" to match their current docs.`)

- [ ] **Step 4: Run tests — expect pass**

```bash
tuist test InfrastructureTests -- -only-testing:InfrastructureTests/CopilotInternalAPIProbeTests
```

Expected: all tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Copilot/CopilotInternalAPIProbe.swift \
        Tests/InfrastructureTests/Copilot/CopilotInternalAPIProbeTests.swift
git commit -m "feat(copilot): rename to AI credits, switch to Monthly quota, populate resetsAt"
```

---

### Task 3: Update `CopilotUsageProbe` (billing mode) — same terminology + `resetsAt`

**Files:**
- Modify: `Sources/Infrastructure/Copilot/CopilotUsageProbe.swift`
- Modify: `Tests/InfrastructureTests/Copilot/CopilotUsageProbeTests.swift`

- [ ] **Step 1: Update existing tests**

In `Tests/InfrastructureTests/Copilot/CopilotUsageProbeTests.swift`, change assertions:

- Every assertion that checks `quotaType == .session` → `quotaType == .timeLimit("Monthly")`.
- Every assertion of `resetText` containing `"requests"` (including the `"(manual)"` variant) → contains `"AI credits"`.
- Add `resetsAt` assertions where the probe is expected to return a populated quota:

```swift
#expect(quota.resetsAt != nil)
```

- Add a new test that specifically asserts the reset date is the first of next month UTC:

```swift
@Test("populates resetsAt as first of next UTC month")
func resetsAtIsFirstOfNextMonth() async throws {
    // arrange probe with a known monthlyLimit and stubbed billing response (use existing helper)
    let snapshot = try await probe.probe()
    let quota = try #require(snapshot.quotas.first)
    let utc = Calendar(identifier: .gregorian)
    var cal = utc; cal.timeZone = TimeZone(identifier: "UTC")!
    let now = Date()
    let comps = cal.dateComponents([.year, .month], from: now)
    let start = try #require(cal.date(from: comps))
    let expected = try #require(cal.date(byAdding: .month, value: 1, to: start))
    #expect(quota.resetsAt == expected)
}
```

(If the file is XCTest-style, convert to `XCTAssertEqual` accordingly.)

- [ ] **Step 2: Run tests — expect failure**

```bash
tuist test InfrastructureTests -- -only-testing:InfrastructureTests/CopilotUsageProbeTests
```

Expected: failures on quota type, `resetsAt`, and "requests" strings.

- [ ] **Step 3: Modify `CopilotUsageProbe.swift`**

At the two `UsageQuota` construction sites (~lines 220 and 235 in the current file; the two `resetText` strings are at lines 242-243):

```swift
// First construction (path where used <= monthlyLimit or used == 0 — confirm by reading the file)
let quota = UsageQuota(
    percentRemaining: percentRemaining,
    quotaType: .timeLimit("Monthly"),
    providerId: "copilot",
    resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
    resetText: "\(Int(used))/\(Int(monthlyLimit)) AI credits"
)

// Manual-override branch:
let quota = UsageQuota(
    percentRemaining: percentRemaining,
    quotaType: .timeLimit("Monthly"),
    providerId: "copilot",
    resetsAt: MonthlyResetDate.nextMonthlyResetDate(),
    resetText: "\(Int(used))/\(Int(monthlyLimit)) AI credits (manual)"
)
```

Replace any log strings that mention "premium requests" with "AI credits" (e.g. the debug line `// Use configured monthly limit or default to 50 (Free/Pro tier premium requests)` → `// Use configured monthly limit or default to 50 (Free/Pro tier AI credits)`).

Leave the URL path `/users/{username}/settings/billing/premium_request/usage` unchanged — GitHub has not yet deprecated it, and the user opted to keep hitting it.

- [ ] **Step 4: Run tests — expect pass**

```bash
tuist test InfrastructureTests -- -only-testing:InfrastructureTests/CopilotUsageProbeTests
```

Expected: all tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/Copilot/CopilotUsageProbe.swift \
        Tests/InfrastructureTests/Copilot/CopilotUsageProbeTests.swift
git commit -m "feat(copilot): update billing probe to AI credits + Monthly quota + resetsAt"
```

---

### Task 4: Update `CopilotProvider` tests for new quota type

**Files:**
- Modify: `Tests/DomainTests/Provider/Copilot/CopilotProviderTests.swift`

- [ ] **Step 1: Read the file to see what quota-type assertions exist**

Open `Tests/DomainTests/Provider/Copilot/CopilotProviderTests.swift` and grep for `.session` or "quota" inside `CopilotProvider` assertions. (The probe tests own the quota-type checks; the provider tests are more about lifecycle and credentials. There's a good chance there are zero changes needed here.)

- [ ] **Step 2: If any test asserts `quotaType == .session` for a Copilot snapshot, change it to `.timeLimit("Monthly")`**

```swift
// If present:
#expect(snapshot.quotas.first?.quotaType == .session)
// Change to:
#expect(snapshot.quotas.first?.quotaType == .timeLimit("Monthly"))
```

- [ ] **Step 3: Run tests — expect pass**

```bash
tuist test DomainTests -- -only-testing:DomainTests/CopilotProviderTests
```

Expected: green (or skipped if no changes needed).

- [ ] **Step 4: Commit (only if changed)**

```bash
git add Tests/DomainTests/Provider/Copilot/CopilotProviderTests.swift
git commit -m "test(copilot): update provider tests to assert Monthly quota type"
```

If no changes were needed, skip this commit.

---

### Task 5: Update `CopilotConfigCard` UI strings

**Files:**
- Modify: `Sources/App/Views/Settings/CopilotConfigCard.swift`

- [ ] **Step 1: Rename the card subtitle**

Line 116 area:

```swift
// Before:
Text("Premium usage tracking")
// After:
Text("AI credits usage tracking")
```

- [ ] **Step 2: Rename the "MONTHLY PREMIUM REQUEST LIMIT" section label**

Line 315:

```swift
// Before:
Text("MONTHLY PREMIUM REQUEST LIMIT")
// After:
Text("MONTHLY AI CREDITS LIMIT")
```

- [ ] **Step 3: Rename the explanatory note**

Line 343:

```swift
// Before:
Text("Note: This is for premium requests (Copilot Chat with advanced models), not code completions")
// After:
Text("Note: This is for AI credits (Copilot Chat with advanced models), not code completions")
```

- [ ] **Step 4: Rename the "CURRENT PREMIUM REQUEST USAGE" section label**

Line 397:

```swift
// Before:
Text("CURRENT PREMIUM REQUEST USAGE")
// After:
Text("CURRENT AI CREDITS USAGE")
```

- [ ] **Step 5: Rename the input hint**

Line 449:

```swift
// Before:
Text("Enter request count (e.g., 99) or percentage (e.g., 198%)")
// After:
Text("Enter AI credits used (e.g., 99) or percentage (e.g., 198%)")
```

- [ ] **Step 6: Build and confirm no other compile breakage**

```bash
tuist build
```

Expected: success. (No logic changes — only string literals.)

- [ ] **Step 7: Commit**

```bash
git add Sources/App/Views/Settings/CopilotConfigCard.swift
git commit -m "feat(copilot): rename settings card labels to AI credits"
```

---

### Task 6: Update acceptance tests

**Files:**
- Modify: `Tests/AcceptanceTests/CopilotConfigSpec.swift`

- [ ] **Step 1: Read the file and look for quota-type, resetText, or other renamed-string assertions**

The acceptance tests likely cover credential management and config flows. The probe-output assertions inside it (if any) need to match the new strings and quota type.

- [ ] **Step 2: Update any `quotaType == .session` to `.timeLimit("Monthly")`**

- [ ] **Step 3: Update any `"requests"` literal assertions to `"AI credits"`**

- [ ] **Step 4: Run tests — expect pass**

```bash
tuist test AcceptanceTests
```

Expected: green.

- [ ] **Step 5: Commit (only if changed)**

```bash
git add Tests/AcceptanceTests/CopilotConfigSpec.swift
git commit -m "test(copilot): update acceptance spec to AI credits + Monthly quota"
```

---

### Task 7: Run the full test suite and `tuist build`

**Files:** (none modified)

- [ ] **Step 1: Run the full test suite**

```bash
tuist test
```

Expected: every target green.

- [ ] **Step 2: Run a release build to catch any issues in the App target**

```bash
tuist build ClaudeBar -C Release
```

Expected: success.

- [ ] **Step 3: Manual smoke check (optional, recommended)**

If you have a Copilot account configured, launch the app and confirm:
- The card header now shows "Monthly" (from `quotaType.displayName`).
- The reset info row shows "Resets in 12d" (or similar) instead of "10/50 requests".
- Settings → Copilot Configuration shows the new labels.

---

## Self-Review

**Spec coverage:**
- ✅ "AI Credits" verbiage: Tasks 2, 3, 5, 6 rename all user-facing strings.
- ✅ Card title "Monthly": Task 2 + 3 set `quotaType: .timeLimit("Monthly")` → `displayName == "Monthly"` (no explicit `quotaType.displayName` override needed in `WrappedStatCard`/`QuotaCardView`).
- ✅ Reset countdown: Tasks 2 + 3 populate `resetsAt` via `MonthlyResetDate`; `WrappedStatCard` already prefers `resetTimestampDescription` (e.g. "Resets in 12d") over `resetText`.

**Placeholder scan:** No "TODO" / "TBD" / "fill in details" placeholders. All code shown. Where the exact line number in a probe is uncertain, the instruction is to read the file to confirm — that's a read, not a placeholder.

**Type consistency:** `quotaType: .timeLimit("Monthly")` is referenced consistently. `MonthlyResetDate.nextMonthlyResetDate(referenceDate:)` signature is used identically in both probes. `resetsAt: MonthlyResetDate.nextMonthlyResetDate()` matches the `UsageQuota.init(resetsAt: Date?)` parameter.

**Out of scope (intentionally not changed):**
- Internal API URL path stays (`/copilot_internal/user`) — the wire field is still `premium_interactions`.
- Billing API URL path stays (`/premium_request/usage`) — per user direction.
- JSON settings keys (`copilot.monthlyLimit`, etc.) stay — per user direction.
- UserDefaults credential keys stay.
- Other providers (Cursor, MiniMax, Kimi) that also use "requests" are out of scope — they have their own billing models that have not changed.
- The probe doc comments that mention "premium request" / "premium_interactions" stay or get a one-line note (since they describe wire-format terms, not user-facing terms).

**No new QuotaType case needed:** `timeLimit("Monthly")` already produces `displayName == "Monthly"` and `duration == .days(30)`. Adding a `.monthly` case would have rippled into every `switch quotaType` and required `quotaKey` migration.

---

## Risks & Open Questions

- **"Resets in" wording vs. GitHub's actual billing semantics.** GitHub's docs say "monthly cycle" and a billing date based on the user's signup day for the first month, then "same days of subsequent months." This plan uses the simpler 1st-of-month UTC model. If you want to honor the actual per-user billing date, we'd need a new settings field (`copilot.billingCycleDay: Int?`) and a more complex `MonthlyResetDate.next(after:byDay:)` helper. Flag if this matters.
- **Card title duplication.** Other providers (e.g. Kimi) also produce "Weekly" or "Session" labels through `quotaType.displayName`. The "Monthly" header is now a Copilot-specific coincidence, not a generic concern. If the design team later wants Copilot to have a unique card title (e.g. "GitHub AI Credits"), that would need a provider-name override in `WrappedStatCard`. Out of scope here.
- **Manual override hint.** The current hint "Enter request count (e.g., 99) or percentage (e.g., 198%)" was renamed to "Enter AI credits used...". Confirm the new wording in Task 5, Step 5 — some users may prefer "Enter AI credits" alone to keep the field terse.
