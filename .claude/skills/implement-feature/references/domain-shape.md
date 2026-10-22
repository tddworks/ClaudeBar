# Think the domain first

Before any change, a fix too, ask how the domain should be, not only where the line fits. The aim is a domain that is **easy to understand**: someone new reads a type's public surface and can explain it in the person's words. We borrow from DDD only what serves that; no pattern is added for its own sake.

The Swift patterns are in [domain-models.md](domain-models.md); the laws and their owners in the [design docs](../../../../docs/architecture/ARCHITECTURE.md).

## Seven questions

The first five keep a type easy to understand; the last two keep it clean as the code grows: **one reason to change (SRP)** and **each concern on its own side (separation of concerns)**.

**1. Would the person say it?**
Names come from the screen and the person ([CANONICAL_MODEL](../../../../docs/architecture/CANONICAL_MODEL.md)), never from the mechanism. Start from their problem: if the facts need a concept the code doesn't have, it is hiding somewhere as optionals or a flag. *A Mac asking to join the leaderboard is its own `DeviceRequest`, not `joining` plus three optionals inside the membership.*

**2. Does the thing decide about itself, and is it the only one that does?**
A rule lives on the thing it is about; callers tell it, they don't read its state and decide. *`QuotaAlerts.add(_:)` checks every rule and throws a `Refusal` Settings prints; `Setting.value(from:)` instead of `setting.default ?? options.first` at each caller.*
**Before you write a rule, search for it.** How fast a quota is spent, a threshold crossed once, the unit a range is counted in, the worst quota of a login: each already has one owner (CANONICAL §5). A second copy drifts, and the screen then contradicts itself. Use the owner, or move the rule to one owner in the same change. *Every reading of how fast a quota is spent (pace, status, a forecast) is a read of one rate on `UsageQuota`, so a card can never say "on track" and "runs out" at once.*

**3. Can you see every state?**
Each state the person can meet is a case, carrying its data; one value never means two things. *"Not read yet" and "nothing used" are two cases, never one `nil`, so a view can tell "on its way" from "none".*

**4. Is it as small as it can be?**
A plain value when it is data with rules; a class only when it changes over time; a protocol only at the outside world (files, network, processes, Keychain), so tests can stub it. No type, layer or flag the change doesn't need. *`SignedInFolder.goesWithAccount` is a value answering one question, tested on its own.*

**5. Is what differs between providers data?**
A definition, or a handle that is `nil` when not declared; never a `switch` on an id or a vendor name in a module. *`account.usageHistory`, `provider.inUse`.*

**6. Does it change for one reason? (SRP)**
Name the reasons a type would change. More than one means a concept is hiding inside it: give each concept the person names its own small value, built from the one below it, holding its data and its behaviour together.
- *A new kind of question is a new value, not another read.* `Days` is a range: its days, the units it offers, a day's value in a unit. "Which models do I lean on" is a value built from it, `ModelMix(of: days, in: unit)`; "what does my year look like" is another. Anything that needs a top model reuses the mix instead of counting again.
- *A rule's data and its behaviour live on one type.* A setting the rule declares (how often to tell, when to stop) is carried out by that rule, not by an engine that also keeps memory of it.
- *A value that adds up owns its own sum.* `ModelUsageLine + ModelUsageLine`, not a field-by-field rebuild in each caller, which silently drops the next field.
- *What differs only in data is one type.* Several structs that are each a cost-and-tokens pair, each with its own "value in the unit", are one value read in a unit.
- *Build only what a caller uses now.* A type, case or setting nothing reads is a reason to change with no user. Add it with the feature that shows it.

**7. Is each concern on its own side? (separation of concerns)**
| Concern | Lives in | Never in |
|---|---|---|
| facts and rules: sums, shares, rates, thresholds, which unit, what is worst | the kernel (`Quotas`) or the context's domain type | a view, a builder in `App`, an adapter |
| one way to write an amount the value owns: `formattedCost`, `formattedDollarUsed` | the value, through the shared formatter (`MoneyFormat`) | a second formatter for the same amount |
| a screen's sentences, labels and chip names | the App's words type (`QuotaCardText`, a view's own `label`) | the kernel: a `summary` sentence, a `String` raw value used as a chip, an outcome's `message` |
| colours, shading bands, layout in rows or weeks | the App (`ModelColors`, the theme) | the kernel: a 0…4 "level" that exists for a five-square legend |
| what the person saved | `settings.json` through `JSONSettingsRepository` ([settings.md](../../../../docs/settings.md)) | a feature's own file |
| a secret the Keychain refuses | the one Keychain-with-fallback store | a copy beside a feature's repository |
| an OS or network fact | one port, one question ([MODULAR_DESIGN §10](../../../../docs/architecture/MODULAR_DESIGN.md)) | a guard in the caller, an `#if os` in neutral code |

A view **renders and tells**: it holds the unit the person picked and passes it in; it never compares units (`days.unit == .cost ? … : …`), picks a login, or maps an empty id to "every login".

## A new feature next to an old one

A feature that sounds new often answers a question the domain already answers, for another destination or another screen. Before adding an engine, ask **who already owns the decision**, and add only what is new:

| The feature is… | The decision already lives in | So the new part is only |
|---|---|---|
| telling someone else (a webhook, a phone) | the alert that decides when to tell (`QuotaAlerts`) | a destination, as Notify! is |
| a new line on a card | the value the card shows (`UsageQuota`, its `Window`) | a read of that value |
| a new period or summary of usage | `Days` and the values built from it | a range (`DateRange`) and a value over the ranges |

## Check by context

The seven questions look at one type. To find what is wrong across the domain, check each **context** ([CANONICAL_MODEL §7](../../../../docs/architecture/CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) as a whole, with six more. Each names a smell you can grep for; the examples are the open findings in [CANONICAL §8](../../../../docs/architecture/CANONICAL_MODEL.md#8--where-the-code-is-still-behind).

| # | Ask | The smell | Example |
|---|---|---|---|
| 1 | **Does anything cross the fence?** Only a reference (an id, a name, a value of the Quota kernel) may | another context's type inside this one's model; reading its storage or factory | `Provider` and `Account` write storage keys (`plainLoginKey`, `verifiedAtLeastOnce`) instead of telling a port |
| 2 | **Does every word mean one thing here?** | one name for two facts, two names for one | `providerId` is the product in one place and the login in the next |
| 3 | **Does every law have one owner?** | the same rule written twice, drifting apart; a caller reading state to decide | *the login with the most left* is computed in `Accounts.best`, `InUse` and `SwitchWhenLow` |
| 4 | **Is the business above, and the technique below?** | argv, paths, JSON keys or OS calls handed to a worker to put together; a business rule in an App driver | the Keychain reader builds `security` argv; the menu-bar driver decides which logins refresh in the background |
| 5 | **Does a new case add data, not an edit?** (SRP, OCP) | a `switch` on an id, a vendor or theme name in shared Swift; one type changing for several reasons | `theme.id == "christmas"` in the popover |
| 6 | **Does the question have a home?** | a context's words and rules scattered over modules, or living in the composition root | Usage History is split over Quotas, Providers, DataSources and the Monitor |

A finding is a row in CANONICAL §8 when a law already says what is right, or a question in §9 when the design must decide first.

## An example: the chart that came in late

The bug: on the first open, *Daily usage — last 30 days* appeared after the rest of the popover, and a fix at the view removed its fade. Asking the first five questions of `UsageHistory` finds the cause in the domain instead.

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
- Two open changes touching the same type agree on one owner first; the second rebases on the first, it doesn't add its own copy.
- A new aggregate, a moved law or a changed owner is a design change: `design.md` first, confirmed before code ([AGENTS.md](../../../../AGENTS.md#design-docs-are-the-source-of-truth)).
- When it isn't obvious, draw now beside proposed as a few lines of ASCII:

```
 NOW                                 PROPOSED
 LeaderboardMembership               DeviceRequest (new Mac only) ──handOver──▶ LeaderboardMembership
  ├─ member stuff                                                                 └─ member stuff only
  └─ joining stuff ◀── both here
```
