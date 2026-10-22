# Think the domain first

Before any change, a fix too, ask how the domain should be, not only where the line fits. The aim is a domain that is **easy to understand**: someone new reads a type's public surface and can explain it in the person's words. We borrow from DDD only what serves that; no pattern is added for its own sake.

The Swift patterns are in [domain-models.md](domain-models.md); the laws and their owners in the [design docs](../../../../docs/architecture/ARCHITECTURE.md).

## Seven questions

The first five keep a type easy to understand; the last two keep it clean as the code grows: **one reason to change (SRP)** and **each concern on its own side (separation of concerns)**.

**1. Would the person say it?**
Names come from the screen and the person ([CANONICAL_MODEL](../../../../docs/architecture/CANONICAL_MODEL.md)), never from the mechanism. Start from their problem: if the facts need a concept the code doesn't have, it is hiding somewhere as optionals or a flag. *#540: a Mac asking to join lived inside the membership as `joining` plus three optionals; it became `DeviceRequest`.*

**2. Does the thing decide about itself, and is it the only one that does?**
A rule lives on the thing it is about; callers tell it, they don't read its state and decide. *`QuotaAlerts.add(_:)` checks every rule and throws a `Refusal` Settings prints; `Setting.value(from:)` instead of `setting.default ?? options.first` at each caller.*
**Before you write a rule, search for it.** The rate a quota is spent at, a threshold crossed once, the unit a range is counted in, the worst quota of a login: these already have owners (CANONICAL §5). A second copy drifts, and the screen then contradicts itself. Use the owner, or move the rule to one owner in the same change. *#596 added a fourth `used ÷ elapsed` beside `burnRate`, `PaceLevel` and `QuotaStatus`, with its own floor; one card read "On track" and "Runs out in 2h". #599 rebuilt `QuotaAlerts`' "once until it climbs back" in a `RuleEngine`, and the two released at different points.*

**3. Can you see every state?**
Each state the person can meet is a case, carrying its data; one value never means two things. *`UsageHistory.lastThirtyDays` is `nil` both before the first read and after thirty empty days, so the view couldn't tell "on its way" from "none" (#536).*

**4. Is it as small as it can be?**
A plain value when it is data with rules; a class only when it changes over time; a protocol only at the outside world (files, network, processes, Keychain), so tests can stub it. No type, layer or flag the change doesn't need. *`SignedInFolder.goesWithAccount` is a value answering one question, tested on its own.*

**5. Is what differs between providers data?**
A definition, or a handle that is `nil` when not declared; never a `switch` on an id or a vendor name in a module. *`account.usageHistory`, `provider.inUse`.*

**6. Does it change for one reason? (SRP)**
Name the reasons a type would change. More than one means a concept is hiding inside it: give each concept the person names its own small value, built from the one below it, and give it its data and its behaviour together.
- *A type that gains a read for every page gains a reason for every page.* #598 made `Days` the owner of the unit, the totals, the model mix, each day's shade and the cache savings. The concepts the person names became their own values over `Days`: `ModelMix(of: days, in: unit)` ("which models do I lean on") and `DayActivity(of: days, in: unit)` ("what does my year look like"). #597's recap then reuses them instead of copying them.
- *Data on one type, behaviour on another, is a rule with no home.* #599 declared `Rule.Throttle` on the rule and carried it out in `RuleEngine`, which also tracked rule edits to reset its memory.
- *A value that adds itself up owns its own sum.* `ModelUsageLine + ModelUsageLine`, not a field-by-field rebuild in every caller, which silently drops the next field.
- *What differs only in data is one type.* Four structs that are each a cost-and-tokens pair, each with its own `value(of:knowsCost:)`, are one value read in a unit.
- *Build only what a caller uses now.* A type, case or setting nothing reads (#598's `Streak`, `Unit.workingTime`) is a reason to change with no user. Add it with the feature that shows it.

**7. Is each concern on its own side? (separation of concerns)**
| Concern | Lives in | Never in |
|---|---|---|
| facts and rules: sums, shares, rates, thresholds, which unit, what is worst | the kernel (`Quotas`) or the context's domain type | a view, a builder in `App`, an adapter |
| one way to write a fact the value owns: `formattedCost`, `formattedDollarUsed` | the value, through the shared formatter (`MoneyFormat`) | a second formatter for the same amount |
| a screen's sentences, labels and chip names: "Runs out in 2h — 11m before it resets", "Cost" | the App's words type (`QuotaCardText`, a view's own `label`) | the kernel (`Forecast.summary`, a `String` raw value on `Days.Unit`, `RuleOutcome.message`) |
| colours, shading bands, layout in weeks or rows | the App (`ModelColors`, `UsageHeatmap`, the theme) | the kernel (`DayValue.level` 0…4 for a five-square legend) |
| what the person saved | `settings.json` through `JSONSettingsRepository` ([settings.md](../../../../docs/settings.md)) | a feature's own file (#599's `rules.json`) |
| a secret the Keychain refuses | the one Keychain-with-fallback store | a copy beside a feature's repository |
| an OS or network fact | one port, one question ([MODULAR_DESIGN §10](../../../../docs/architecture/MODULAR_DESIGN.md)) | a guard in the caller, an `#if os` in neutral code |

A view **renders and tells**: it holds the unit the person picked and passes it in; it never compares units (`days.unit == .cost ? … : …`), picks a login, or maps an empty id to "every login".

## A new feature next to an old one

A feature that sounds new often answers a question the domain already answers, for another destination or another screen. Before adding an engine, ask **who already owns the decision**, and add only what is new:

| The feature | Already decided by | So the new part is |
|---|---|---|
| post quota alerts to a webhook (#599) | `QuotaAlerts`: crossed below X%, once until it climbs back | a destination (`WebhookAnnouncer`), like Notify! |
| a forecast on the quota card (#596) | the quota's rate and its `Window` | a read of the rate |
| a weekly recap (#597) | `Days` and its values: totals, mix, busiest day | a range, `DateRange.week(containing:)`, and a value over the ranges |

## Check by context

The seven questions look at one type. To find what is wrong across the domain, check each **context** ([CANONICAL_MODEL §7](../../../../docs/architecture/CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) as a whole, with six more. Each names a smell you can grep for; each example is one the [October 2026 review](../../../../docs/architecture/CANONICAL_MODEL.md#8--where-the-code-is-still-behind) found.

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
