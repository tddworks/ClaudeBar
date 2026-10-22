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

And when the week is done, a person asks one more thing: **can I keep this, or
send it?** The card lives in a popover — closed, it is gone. A **report** is
the recap written out: one self-contained HTML file, saved where the person
says, opened anywhere. It holds what the card says — the total, the change, the
split, the highlights — and the shape behind them, the day by day and the model
by model, each read from its own owner. The person drives it: a button on the
card, a save panel, one file. The app never reads the file back — the days stay
the record.

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
| a **month** | the calendar's month holding a day (`DateRange.month`); the month before is one calendar month earlier, never a day-count back — months differ in length | a fixed 30 days; the last thirty days |
| the **unit** | what the whole recap is read in: cost or tokens, the one every provider offers | a unit per provider |
| a **part** | one provider's total in the unit, and its share of the week | a login: two logins of one provider are one part |
| the **change** | the week against the week before, as a fraction | a change against a range with nothing in it |
| **tokens** | what `Days` and the chart count: input and output, never the cache | `totalTokensWithCache` |
| a **report** | the recap written out as one HTML file: what the card says, plus the day-by-day and model-by-model shape; saved only when the person saves it | a stored report the app reads back; an automatic share; a second source of days |

## 3 · The model

```
DateRange.week(containing:calendar:)       the calendar's week                    Quotas
DateRange.before(calendar:)                the same run one run earlier           Quotas
DateRange.month(containing:calendar:)      the calendar's month                   Quotas
DateRange.previousMonth(calendar:)         one calendar month earlier — months differ in length, so a month steps a month, never a day-count back   Quotas

per provider id:  usageHistory.days(in: week), usageHistory.days(in: week.before)
                  (two logins of one provider: Days.merged)

Recap(this: [String: Days], before: [String: Days])                               Quotas
 ├ unit        cost when every range that used anything offers cost, else tokens   ← one owner
 ├ total       Σ days.total(in: unit)
 ├ change      (total − before) / before; nil when before is 0
 ├ providers   [Part]  provider · value · share — largest first, ties by id; a provider that used nothing is left out
 ├ topModel    ModelMix(of: merged, in: unit).top                                  (ModelMix)
 ├ models      ModelMix(of: merged, in: unit).parts — every model, largest first   (ModelMix)
 ├ biggestDay  DayActivity(of: merged, in: unit).busiest                           (DayActivity)
 ├ days        DayActivity(of: merged, in: unit).days — every day, oldest first    (DayActivity)
 ├ cacheSavings · workingTime · sessions      plain sums of merged
 ├ tokens      the week in tokens beside a total in another unit; nil when the unit is tokens
 └ isEmpty     no provider used anything

Days.merged([Days])         several ranges as one: each date once, its days added (DailyUsageStat +)
DailyUsageStat +            two days of one date as one: every count, cost, time, savings; one line per model (ModelUsageLine +)
```

| Type | Answers | Where |
|---|---|---|
| `DateRange.week` | the calendar's week holding a day | `Modules/Quotas/Sources/DateRange.swift` |
| `DateRange.month` | the calendar's month holding a day; the month before is one calendar month earlier | `Modules/Quotas/Sources/DateRange.swift` |
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
biggest day in the person's locale. The weeks are `RecapRange`'s (Domain); its
chip names and *vs last week* are the App's words for it.

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
| the recap is read again only when the week turned, the lineup changed, or a login's days were read again since the last read that finished; otherwise the last read stands, and a cancelled read is read again next time | `WeeklyRecaps` |
| a range that read nothing has no say in whether the merged range is priced | `Days.merged` |
| a value is written once per unit | `UsageFormat` (App) |
| the report holds what the card holds, in the card's words, plus the day-by-day and model-by-model shape read from their own owners — never a second count; it is written only when the person saves it, and the app never reads it back | `Recap.days` · `Recap.models` · `RecapHTMLReport` (App) |
| the report travels alone: its own stylesheet, no script, the system's light or dark — not the app's theme | `RecapHTMLReport` (App) |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `Recap`, `DateRange.week`, `DateRange.month`, `Days.merged`, `DailyUsageStat +` | the values | `Modules/Quotas/Sources/` |
| `WeeklyRecaps` | the lineup's recaps: asks each login for `usageHistory.days(in:)` for every range and the range before each, by provider (`Days.merged`), and builds a `Recap` per range. Owns when it is read again (`readIfStale`): the ranges it was read for against now, and each login's last read. It cuts no days and picks no unit. Built in `ClaudeBarApp.init()` over the `QuotaMonitor`'s lineup; tests hand it `RecapLogin`s, a clock and a calendar | `Sources/Domain/UsageHistory/` |
| `RecapRange` | *This week* / *Last week* / *This month* / *Last month*: the range it names (`DateRange.week`, or the month rule) | `Sources/Domain/UsageHistory/` |
| `RecapRange` words | the chip's name, what it is compared with, its empty note | `Sources/App/UsageHistory/RecapRange+Words.swift` |
| `RecapCardView` | renders a recap and tells: the range chips, the total in `recap.unit`, the change and what it is against, each provider's part, the highlights — and offers the report when the chosen recap holds something | `Sources/App/UsageHistory/` |
| the All page (`MenuContentView`) | shows the card while the person shows the **Weekly recap** section (`UsageSection.weeklyRecap`, on by default, through `AppSettingsRepository.isShown`), and tells `WeeklyRecaps` to read if stale when the card appears and after the logins' usage is read | `Sources/App/Views/` |
| `UsageFormat` | a value in a unit, a share, a change, a duration | `Sources/App/UsageHistory/` |
| `RecapHTMLReport` | the recap as one self-contained HTML page: the card's words (`UsageFormat`, `RecapRange`'s), the day-by-day and model-by-model shape from `Recap.days` / `Recap.models`, pure CSS, no script, the system's light or dark, everything escaped. Mocked up at [design-concept/recap/report.html](../../../../design-concept/recap/report.html) | `Sources/App/UsageHistory/` |
| the report writer | the person's one gesture: the save panel (named for the range), the atomic write, the file opened when saved. View-side plumbing, kept thin | `Sources/App/UsageHistory/` |

```
 card appears · usage read (monitor.readToday)
   └─ WeeklyRecaps.readIfStale()      nothing when the ranges and each login's lastThirtyDays are the ones it read for
        for This week, Last week, This month, Last month:
          this   = each provider's days(in: range)          ← UsageHistory.days(in:)
          before = each provider's days(in: range.before)
          Recap(this:, before:)
   └─ RecapCardView(recaps:, dates:, name:) → the chosen range's recap, its RecapRange's words; an empty range says so, the chips stay
         └─ export button → save panel → RecapHTMLReport(recap:, range:, dates:, name:) → file, opened
```

Both ranges of a kind are read together, so the chips are there whichever holds
usage, and switching reads nothing. The change's label comes from the same
`RecapRange` the recap was read for, so it always names the range before the
one on screen. The days come from the ledger for closed days and from the logs
only for the open ones (daily-usage), so reading four ranges costs little.

The card is shown while the **Weekly recap** usage section is: `UsageSection`
owns its default (shown), the person's switch in Settings → General overrides
it, and the settings repository keeps the choice. It needs the All page,
which is offered from two providers.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a month recap | `RecapRange`: a case and the range it names (a `DateRange` rule beside `week`) |
| another highlight (a median day, cost per session) | a value built from `Days`, read in `recap.unit` — never a count in the card |
| another tool in the recap | its definition's `usageHistory`; the recap reads whatever days a login has |
| the week to start on Sunday | the person's calendar — no code |
| provider colours from the provider's look | the card: its palette; nothing in the kernel |
| the report to look different | its stylesheet — one place, the report's own; the words stay `UsageFormat`'s |
| another section in the report | a value built from `Days` in `recap.unit` (`Recap.days`, `Recap.models`), never a count in the report |

## 7 · Considered and rejected

| Considered | Rejected because |
|---|---|
| cost whenever any provider prices its days | an unpriced provider counts as $0: the total mixes units and the split drops it |
| a cost-and-tokens pair per highlight (totals, share, top model, biggest day), each with its own value in the unit | one rule written four times; the unit is `Days`' and the reads are `ModelMix`'s and `DayActivity`'s |
| tokens with the cache in them | the chart counts input and output; one person would see two totals for one week |
| formatting in the kernel | words, dates and locales are the App's; the kernel holds numbers |
| the card cutting each week out of `lastThirtyDays` | cutting a range is `UsageHistory.days(in:)`'s job |
| a stored weekly report | the days are the record; a kept recap is a second truth |
| the report in the person's app theme | the file travels alone: its own stylesheet keeps it self-contained and follows the system's light or dark, not a theme the reader doesn't have |
| the report rebuilding the day-by-day from `lastThirtyDays` | the shape is `DayActivity`'s and `ModelMix`'s read of the merged range; a second cut is a second truth |
| a card that reads only the chosen week | the chips would vanish on an empty week, and the change label could name a week the recap wasn't read for |

## 8 · Deferred, and open

- **The shareable image** and **the Mac's Monday notification** are not
  built. The image is the one place repo or model names could leave the Mac
  *without the person driving*, so it goes through the Leaderboard's *exactly
  what gets shared* step; the notification is a destination beside Notify!,
  never a Monitor edit. What **is** built of the Monday idea is the webhook
  send — [recap alerts](../../alerting/recap-alerts/design.md), whose
  `RecapAlerts` tells the recap destinations at the week's turn; the Mac's
  notification is a second destination when it comes. The **HTML report** is
  built too, and needs no gate: like a clipboard copy, it leaves the Mac only
  through the person's own save.
- **A one-provider Mac** has no All page, so no recap. Whether it belongs under
  *TODAY'S USAGE* there is open.
- **This week is partial.** Whether the card says *so far* is a wording question.
