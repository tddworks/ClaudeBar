# Weekly recap — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). The days it reads:
> [daily-usage](../daily-usage/design.md). The values it reuses — `ModelMix`,
> `DayActivity`: [insights](../insights/design.md).

> **Status: BUILT.** Mockup: [design-concept/recap](../../../../design-concept/recap/index.html).

## 1 · What a person asks, and what is true

Once a week a person stops and asks: **what did all of it add up to?** Not one
login's day — *TODAY'S USAGE* and the chart answer that — but the week across
every provider: what it came to, which tools it was spent on, which model did
the most, which day was the heaviest, what caching saved, and whether it was
more or less than the week before.

A recap is **a read of a range, across providers**. It adds no source, no store
and no fetch: each login's days are `account.usageHistory.days(in:)`, and the
questions it asks of them already have owners — the unit is `Days`', the top
model `ModelMix`'s, the busiest day `DayActivity`'s. What the recap adds is
the **week** as a range and the **one law that reads several providers in one
unit**.

```swift
let week = DateRange.week(containing: now, calendar: calendar)   // the calendar's week
let this   = [providerId: account.usageHistory.days(in: week)]              // per provider
let before = [providerId: account.usageHistory.days(in: week.before(calendar: calendar))]

let recap = Recap(this: this, before: before)
recap.unit          // cost only if every provider that used anything offers cost
recap.total         // Σ days.total(in: unit)
recap.change        // against before; nil when nothing was used before
recap.providers     // one part per provider: value, share — largest first
recap.topModel      // ModelMix(of: merged, in: unit).top
recap.biggestDay    // DayActivity(of: merged, in: unit).busiest
```

## 2 · The words

| Word | Means | Not |
|---|---|---|
| a **recap** | one range across every provider, against the range before it: the total, the change, each provider's part, the top model, the biggest day, what caching saved, the time worked and the sessions | a kept report; a new source of days; a quota |
| a **week** | the calendar's week holding a day, from the calendar's own first weekday, seven days (`DateRange.week`) | a fixed Monday; the last seven days |
| **the week before** | the same run of days one run earlier (`DateRange.before`) | a stored history; a second recap |
| the **unit** | what the whole recap is read in: cost or tokens, the one every provider offers | a unit per provider |
| a **part** | one provider's total in the unit, and its share of the week | a login: two logins of one provider are one part |
| the **change** | the week against the week before, as a fraction | a change against a range with nothing in it |
| **tokens** | what `Days` and the chart count: input and output, never the cache | `totalTokensWithCache` |

## 3 · The model

```
DateRange.week(containing:calendar:)       the calendar's week                    Quotas
DateRange.before(calendar:)                the same run one run earlier           Quotas

per provider id:  usageHistory.days(in: week), usageHistory.days(in: week.before)
                  (two logins of one provider: Days.merged)

Recap(this: [String: Days], before: [String: Days])                               Quotas
 ├ unit        cost when every range that used anything offers cost, else tokens   ← one owner
 ├ total       Σ days.total(in: unit)
 ├ change      (total − before) / before; nil when before is 0
 ├ providers   [Part]  provider · value · share — largest first, ties by id; a provider that used nothing is left out
 ├ topModel    ModelMix(of: merged, in: unit).top                                  (ModelMix)
 ├ biggestDay  DayActivity(of: merged, in: unit).busiest                           (DayActivity)
 ├ cacheSavings · workingTime · sessions      plain sums of merged
 ├ tokens      the week in tokens beside a total in another unit; nil when the unit is tokens
 └ isEmpty     no provider used anything

Days.merged([Days])         several ranges as one: each date once, its days added (DailyUsageStat +)
DailyUsageStat +            two days of one date as one: every count, cost, time, savings; one line per model (ModelUsageLine +)
```

| Type | Answers | Where |
|---|---|---|
| `DateRange.week` | the calendar's week holding a day | `Modules/Quotas/Sources/DateRange.swift` |
| `Recap` | the week across providers, in one unit, against the week before | `Modules/Quotas/Sources/Recap.swift` |
| `Days.merged`, `isEmpty`, `workingTime`, `sessions` | several ranges as one; whether it holds anything; plain sums | `Modules/Quotas/Sources/Days.swift` |
| `DailyUsageStat` `+` | two days of one date as one | `Modules/Quotas/Sources/DailyUsageStat.swift` |

**One unit for the whole recap.** A sum across providers is only honest in a
unit every one of them can say: a provider that prices nothing would count as
$0 in dollars, and the total, the split and the change would quietly drop it.
So the recap reads in cost only when **every provider that used anything** —
this week or the week before — offers cost (`Days.units`), and in tokens
otherwise. A priced provider that sat idle has nothing to say and takes no
vote. The week and the week before are read in the same unit, so the change
compares like with like.

**The merged days answer the cross-provider questions.** The top model and the
biggest day are about the week, not a provider, so the recap merges every
provider's days by date and asks `ModelMix` and `DayActivity` — never a second
count. A day owns its sum (`DailyUsageStat +`), as a line does.

**The words are the App's.** The kernel holds numbers and a unit; the card
writes them: `UsageFormat.value(_:in:)`, `change`, `duration`, a share, and the
biggest day in the person's locale. The chip names and *vs last week* are
`RecapRange`'s.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a week is the calendar's week holding a day, from its own first weekday; the range before is the same length, one run earlier | `DateRange` (`week`, `before`) |
| a recap across providers reads in the unit every range offers: cost only when every provider that used anything, this week or the week before, offers cost; tokens otherwise | `Recap.unit` |
| the change is the week against the week before, in the same unit; no change when nothing was used before | `Recap.change` |
| a recap sums across logins for the person's total and names the providers it spans; two logins of one provider are one part. A login's own chart stays its own | `Recap.providers` |
| the top model is the mix's, the unnamed line never | `ModelMix` |
| the biggest day is the busiest of the merged days | `DayActivity` |
| two days of one date add up to one: every count, the cost, the time, the savings, one line per model | `DailyUsageStat` (`+`) |
| a recap is a read, never stored; a week with nothing is said, never shown as zeros | `Recap.isEmpty` · the card |
| a value is written once per unit | `UsageFormat` (App) |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `Recap`, `DateRange.week`, `Days.merged`, `DailyUsageStat +` | the values | `Modules/Quotas/Sources/` |
| `RecapBuilder` | the composition: asks each login of the lineup for `usageHistory.days(in:)` for both weeks and the week before each, by provider, and builds a `Recap` per week. It cuts no days and picks no unit | `Sources/App/UsageHistory/` |
| `RecapRange` | *This week* / *Last week*: the chip's name, the week it names (`DateRange.week`, or the week before), what it is compared with, its empty note | `Sources/App/UsageHistory/` |
| `RecapCardView` | renders a recap and tells: the range chips, the total in `recap.unit`, the change and what it is against, each provider's part, the highlights | `Sources/App/UsageHistory/` |
| the All page (`MenuContentView`) | reads both weeks when it opens, and again when the week turns, the setting changes or a login's days are read again | `Sources/App/Views/` |
| `UsageFormat` | a value in a unit, a share, a change, a duration | `Sources/App/UsageHistory/` |

```
 All page opens  ─ .task(id: week · Daily Usage Cards · each login's lastThirtyDays)
   └─ RecapBuilder.recaps(of: lineup's usage histories, at: now)
        for This week, Last week:
          this   = each provider's days(in: week)           ← UsageHistory.days(in:)
          before = each provider's days(in: week.before)
          Recap(this:, before:)
   └─ RecapCardView(recaps:, name: provider's name)
        the chosen week's recap, its RecapRange's words; an empty week says so, the chips stay
```

Both weeks are read together, so the chips are there whichever week holds
usage, and switching reads nothing. The change's label comes from the same
`RecapRange` the recap was read for, so it always names the week before the
one on screen. The days come from the ledger for closed days and from the logs
only for the open ones (daily-usage), so reading three weeks costs little.

The card is shown while **Daily Usage Cards** is on, and needs the All page,
which is offered from two providers.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a month recap | `RecapRange`: a case and the range it names (a `DateRange` rule beside `week`) |
| another highlight (a median day, cost per session) | a value built from `Days`, read in `recap.unit` — never a count in the card |
| another tool in the recap | its definition's `usageHistory`; the recap reads whatever days a login has |
| the week to start on Sunday | the person's calendar — no code |
| provider colours from the provider's look | the card: its palette; nothing in the kernel |

## 7 · Considered and rejected

| Considered | Rejected because |
|---|---|
| cost whenever any provider prices its days | an unpriced provider counts as $0: the total mixes units and the split drops it |
| a cost-and-tokens pair per highlight (totals, share, top model, biggest day), each with its own value in the unit | one rule written four times; the unit is `Days`' and the reads are `ModelMix`'s and `DayActivity`'s |
| tokens with the cache in them | the chart counts input and output; one person would see two totals for one week |
| formatting in the kernel | words, dates and locales are the App's; the kernel holds numbers |
| the card cutting each week out of `lastThirtyDays` | cutting a range is `UsageHistory.days(in:)`'s job |
| a stored weekly report | the days are the record; a kept recap is a second truth |
| a card that reads only the chosen week | the chips would vanish on an empty week, and the change label could name a week the recap wasn't read for |

## 8 · Deferred, and open

- **The shareable image** and **the Monday notification** are not built. The
  image is the one place repo or model names could leave the Mac, so it goes
  through the Leaderboard's *exactly what gets shared* step; the notification is
  a destination beside Notify!, never a Monitor edit.
- **A one-provider Mac** has no All page, so no recap. Whether it belongs under
  *TODAY'S USAGE* there is open.
- **This week is partial.** Whether the card says *so far* is a wording question.
