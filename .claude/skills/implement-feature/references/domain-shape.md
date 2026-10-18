# Think the domain first

Before any change, a fix too, ask how the domain should be, not only where the line fits. The aim is a domain that is **easy to understand**: someone new reads a type's public surface and can explain it in the person's words. We borrow from DDD only what serves that; no pattern is added for its own sake.

The Swift patterns are in [domain-models.md](domain-models.md); the laws and their owners in the [design docs](../../../../docs/architecture/ARCHITECTURE.md).

## Five questions

**1. Would the person say it?**
Names come from the screen and the person ([CANONICAL_MODEL](../../../../docs/architecture/CANONICAL_MODEL.md)), never from the mechanism. Start from their problem: if the facts need a concept the code doesn't have, it is hiding somewhere as optionals or a flag. *#540: a Mac asking to join lived inside the membership as `joining` plus three optionals; it became `DeviceRequest`.*

**2. Does the thing decide about itself?**
A rule lives on the thing it is about; callers tell it, they don't read its state and decide. *`QuotaAlerts.add(_:)` checks every rule and throws a `Refusal` Settings prints; `Setting.value(from:)` instead of `setting.default ?? options.first` at each caller.*

**3. Can you see every state?**
Each state the person can meet is a case, carrying its data; one value never means two things. *`UsageHistory.lastThirtyDays` is `nil` both before the first read and after thirty empty days, so the view couldn't tell "on its way" from "none" (#536).*

**4. Is it as small as it can be?**
A plain value when it is data with rules; a class only when it changes over time; a protocol only at the outside world (files, network, processes, Keychain), so tests can stub it. No type, layer or flag the change doesn't need. *`SignedInFolder.goesWithAccount` is a value answering one question, tested on its own.*

**5. Is what differs between providers data?**
A definition, or a handle that is `nil` when not declared; never a `switch` on an id or a vendor name in a module. *`account.usageHistory`, `provider.inUse`.*

## Check by context

The five questions look at one type. To find what is wrong across the domain, check each **context** ([CANONICAL_MODEL §7](../../../../docs/architecture/CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) as a whole, with six more. Each names a smell you can grep for; each example is one the [October 2026 review](../../../../docs/architecture/CANONICAL_MODEL.md#8--where-the-code-is-still-behind) found.

| # | Ask | The smell | Example |
|---|---|---|---|
| 1 | **Does anything cross the fence?** Only a reference (an id, a name, a value of the Quota kernel) may | another context's type inside this one's model; reading its storage or factory | the status alert reads Providers' saved accounts to name a login, instead of taking `lineupName` |
| 2 | **Does every word mean one thing here?** | one name for two facts, two names for one | `providerId` is the product in one place and the login in the next |
| 3 | **Does every law have one owner?** | the same rule written twice, drifting apart; a caller reading state to decide | *the login with the most left* is computed in `Accounts.best`, `InUse` and `SwitchWhenLow` |
| 4 | **Is the business above, and the technique below?** | argv, paths, JSON keys or OS calls handed to a worker to put together; a business rule in an App driver | the Keychain reader builds `security` argv; the menu-bar driver decides which logins refresh in the background |
| 5 | **Does a new case add data, not an edit?** (SRP, OCP) | a `switch` on an id, a vendor or theme name in shared Swift; one type changing for several reasons | `theme.id == "christmas"` in the popover; `"codex."` in an alert |
| 6 | **Does the question have a home?** | a context's words and rules scattered over modules, or living in the composition root | Usage History is split over Quotas, Providers, DataSources and the Monitor |

A finding is a row in CANONICAL §8 when a law already says what is right, or a question in §9 when the design must decide first.

## An example: the chart that came in late ([#536](https://github.com/tddworks/ClaudeBar/pull/536))

The bug: on the first open, *Daily usage — last 30 days* appeared after the rest of the popover, and a fix at the view removed its fade. Asking the five questions of `UsageHistory` finds the cause in the domain instead.

```swift
// NOW (Modules/Providers/Sources/UsageHistory.swift)
public private(set) var lastThirtyDays: Quotas.Days?      // nil: not read yet, OR read and empty

public func read() async {
    …
    lastThirtyDays = month.stats.allSatisfy(\.isEmpty) ? nil : month
}

// the view
if let lastThirtyDays { UsageHistoryChartView(days: lastThirtyDays) }   // arriving? or none?
```

| Question | What it finds |
|---|---|
| 1. Would the person say it? | Yes: *last 30 days* is the card's title. Keep the name |
| 2. Does the thing decide about itself? | No: `read()` reaches into `month.stats` to decide "empty". `Days` should answer `isEmpty` |
| 3. Can you see every state? | No: `nil` is two states the person meets, *still reading* and *nothing used* |
| 4. Is it as small as it can be? | A three-case enum is enough; no new type for the chart, no flag on the view |
| 5. Is what differs data? | Yes already: the definition's `usageHistory` says where the logs are |

```swift
// PROPOSED: the states the person meets, each one a case
public enum LastThirtyDays: Equatable { case notReadYet, nothingUsed, used(Quotas.Days) }
public private(set) var lastThirtyDays: LastThirtyDays = .notReadYet

lastThirtyDays = month.isEmpty ? .nothingUsed : .used(month)   // Days decides

// the view draws each state, and can fade in on .notReadYet → .used
if case .used(let days) = history.lastThirtyDays { UsageHistoryChartView(days: days) }
```

The proposed shape is small: one enum, one new property on `Days`, and the view draws each state instead of guessing. Since it changes what `UsageHistory` says, it goes into the [daily-usage design](../../../../docs/features/usage-history/daily-usage/design.md) first.

## Keep it in scope

- Fix what these questions find **in the types the change touches**, test first. Leave the rest for its own change.
- A new aggregate, a moved law or a changed owner is a design change: `design.md` first, confirmed before code ([AGENTS.md](../../../../AGENTS.md#design-docs-are-the-source-of-truth)).
- When it isn't obvious, draw now beside proposed as a few lines of ASCII:

```
 NOW                                 PROPOSED
 LeaderboardMembership               DeviceRequest (new Mac only) ──handOver──▶ LeaderboardMembership
  ├─ member stuff                                                                 └─ member stuff only
  └─ joining stuff ◀── both here
```
