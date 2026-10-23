# Recap — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). The days it reads:
> [daily-usage](../daily-usage/design.md). The values it reuses — `ModelMix`,
> `DayActivity`: [insights](../insights/design.md).

> **Status: BUILT.** Mockup: [design-concept/recap](../../../../design-concept/recap/index.html).

## 1 · What a person asks, and what is true

Once a week, or a month, a person stops and asks: **what did all of it add up
to?** Not one login's day — *TODAY'S USAGE* and the chart answer that — but the
week or the month across every provider: what it came to, which tools it was spent on, which model did
the most, which day was the heaviest, what caching saved, and whether it was
more or less than the week or month before.

And when the week is done, a person asks one more thing: **can I keep this, or
send it?** The card lives in a popover — closed, it is gone. A **report** is
the recap written out: one self-contained HTML file, saved where the person
says, opened anywhere. It holds what the card says — the total, the change, the
split, the highlights — and the shape behind them, the day by day and the model
by model, each read from its own owner. The person drives it: a button on the
card, a save panel, one file. The card only tells; saving is `ReportSaver`'s,
and a save that fails is shown, not only logged. The app never reads the file back — the days stay
the record.

A recap is **a read of a range, across providers**. It adds no source, no store
and no fetch: each login's days are `account.usageHistory.days(in:)`, and the
questions it asks of them already have owners — the unit is `Days`', the top
model `ModelMix`'s, the busiest day `DayActivity`'s. What the recap adds is
the **period** — a week or a month — as a span, and the **one law that reads
several providers in one unit**.

```swift
let week   = RecapPeriod.week.range(containing: now, calendar: calendar)   // the calendar's week
let this   = [providerId: account.usageHistory.days(in: week)]              // per provider
let before = [providerId: account.usageHistory.days(in: RecapPeriod.week.before(week, calendar: calendar))]

let recap = Recap(range: week, this: this, before: before)
recap.range         // the days it sums — the report's header, the sender's check
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
| a **period** | the span a recap adds up: a week or a month (`RecapPeriod`) | a flag on a range; a day count |
| a **week** | the calendar's week holding a day, from the calendar's own first weekday, seven days (`RecapPeriod.week`, `DateRange.week`) | a fixed Monday; the last seven days |
| a **month** | the calendar's month holding a day, however long it runs (`RecapPeriod.month`, `DateRange.month`) | a fixed 30 days; the last thirty days |
| **the period before** | the period holding the day before this one starts — one rule for a week and a month, so a month steps a month, never a day-count back (`RecapPeriod.before`) | a stored history; a second recap; a day-count back |
| a **range** (`RecapRange`) | *this* or *last* of a period: *This week*, *Last week*, *This month*, *Last month* | the dates themselves (a `DateRange`) |
| the **unit** | what the whole recap is read in: cost or tokens, the one every provider offers | a unit per provider |
| a **part** | one provider's total in the unit, and its share of the range | a login: two logins of one provider are one part |
| the **change** | the range against the period before it, as a fraction | a change against a range with nothing in it |
| **tokens** | what `Days` and the chart count: input and output, never the cache | `totalTokensWithCache` |
| a **report** | the recap written out as one HTML file: what the card says, plus the day-by-day and model-by-model shape; saved only when the person saves it | a stored report the app reads back; an automatic share; a second source of days |

## 3 · The model

```
DateRange.week(containing:calendar:)       the calendar's week — a plain run of days    Quotas
DateRange.month(containing:calendar:)      the calendar's month — a plain run of days   Quotas

RecapPeriod  .week | .month                                                       Domain
 ├ range(containing:calendar:)             the period holding a day
 └ before(_:calendar:)                     the period holding the day before it starts — one rule for both
RecapRange   .this(RecapPeriod) | .last(RecapPeriod)                              Domain
 ├ period                                  the span it adds up — the report's words and chart rhythm
 ├ range(containing:calendar:)             this: period.range · last: period.before(period.range)
 └ rangeBefore(containing:calendar:)       period.before(range)

per provider id:  usageHistory.days(in: range), usageHistory.days(in: rangeBefore)
                  (two logins of one provider: Days.merged; each distinct range asked once)

Recap(range: DateRange, this: [String: Days], before: [String: Days])             Quotas
 ├ range       the days it sums — one owner of "which dates does this recap cover"
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
DailyUsageStat +            two days of one date as one: every count, cost, time, savings; one line per model and per named project (UsageLine +)
```

| Type | Answers | Where |
|---|---|---|
| `DateRange.week`, `DateRange.month` | the calendar's week or month holding a day, as a plain run of days | `Modules/Quotas/Sources/DateRange.swift` |
| `RecapPeriod` | the span a recap adds up, and the period before it | `Sources/Domain/UsageHistory/RecapPeriod.swift` |
| `RecapRange` | this or last of a period, and the range it is read against | `Sources/Domain/UsageHistory/RecapRange.swift` |
| `Recap` | the range across providers, in one unit, against the range before; it carries its dates | `Modules/Quotas/Sources/Recap.swift` |
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
biggest day in the person's locale. The spans are `RecapPeriod`'s and the
ranges `RecapRange`'s (Domain); the chip names, *vs last week* and the period's
word (*week*, *month*) are the App's words for them.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a week is the calendar's week holding a day, from its own first weekday; a month is the calendar's month holding a day, however long it runs | `DateRange` (`week`, `month`) |
| the period before is the one holding the day before this one starts — one rule for a week and a month; this or last of a period names its range | `RecapPeriod` · `RecapRange` |
| a recap carries the days it sums; a header, a report and a sender read them there, never a second answer | `Recap.range` |
| a recap across providers reads in the unit every range offers: cost only when every provider that used anything, this week or the week before, offers cost; tokens otherwise | `Recap.unit` |
| the change is the range against the period before it, in the same unit; no change when nothing was used before | `Recap.change` |
| a recap sums across logins for the person's total and names the providers it spans; two logins of one provider are one part. A login's own chart stays its own | `Recap.providers` |
| the top model is the mix's, the unnamed line never | `ModelMix` |
| the biggest day is the busiest of the merged days | `DayActivity` |
| two days of one date add up to one: every count, the cost, the time, the savings, one line per model | `DailyUsageStat` (`+`) |
| a recap is a read, never stored; a range with nothing is said, never shown as zeros | `Recap.isEmpty` · the card |
| the recap is read again only when a week or month turned, the lineup changed, or a login's days were read again since the last read that finished; otherwise the last read stands, and a cancelled read is read again next time | `Recaps` |
| a range that read nothing has no say in whether the merged range is priced | `Days.merged` |
| a value is written once per unit | `UsageFormat` (App) |
| the report holds what the card holds, in the card's words, plus the day-by-day and model-by-model shape read from their own owners — never a second count; its peak is the recap's biggest day, its dates the recap's range | `Recap.days` · `Recap.models` · `Recap.biggestDay` · `RecapHTMLReport` (App) |
| one list of hues in the App: a model's colour is its place among the range's models in name order, in the chart, the mix and the report alike; a recap's providers take the same hues by their place; the report writes them as hex for light and dark | `ModelColors` (App) |
| a report is saved only when the person saves it, where they say; a write that fails is shown to them; the app never reads it back | `ReportSaver` (App) |
| the report travels alone: its own stylesheet, no script, the system's light or dark — not the app's theme | `RecapHTMLReport` (App) |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `Recap`, `DateRange.week`, `DateRange.month`, `Days.merged`, `DailyUsageStat +` | the values | `Modules/Quotas/Sources/` |
| `Recaps` | the lineup's recaps: asks each login for `usageHistory.days(in:)` for every distinct range — last week is this week's before, so six ranges, not eight — by provider (`Days.merged`), and builds a `Recap` per range, carrying its range. Owns when it is read again (`readIfStale`): the ranges it was read for against now, and each login's last read. It cuts no days and picks no unit. Built in `ClaudeBarApp.init()` over the `QuotaMonitor`'s lineup; tests hand it `RecapLogin`s, a clock and a calendar | `Sources/Domain/UsageHistory/` |
| `RecapPeriod` | *week* / *month*: the period holding a day, and the period before it | `Sources/Domain/UsageHistory/` |
| `RecapRange` | `.this(period)` / `.last(period)`: the range it names, the one it is read against, and its `period` | `Sources/Domain/UsageHistory/` |
| `RecapRange` words | the chip's name, what it is compared with, its empty note, the period's word | `Sources/App/UsageHistory/RecapRange+Words.swift` |
| `RecapCardView` | renders a recap and tells: the range chips, the total in `recap.unit`, the change and what it is against, each provider's part, the highlights — and offers the report when the chosen recap holds something, telling `ReportSaver` to save it and showing a save that failed | `Sources/App/UsageHistory/` |
| `ModelColors` | the App's one list of hues: a model's by its place among the range's models, a provider's by its place in the split, and each as hex for the report | `Sources/App/UsageHistory/` |
| the All page (`MenuContentView`) | shows the card while the person shows the **Recap** section (`UsageSection.weeklyRecap`, a key kept from when it held weeks only; on by default, through `AppSettingsRepository.isShown`), and tells `Recaps` to read if stale when the card appears and after the logins' usage is read | `Sources/App/Views/` |
| `UsageFormat` | a value in a unit, a share, a change, a duration | `Sources/App/UsageHistory/` |
| `RecapHTMLReport` | the recap as one self-contained HTML page: the card's words (`UsageFormat`, `RecapRange`'s), the day-by-day and model-by-model shape from `Recap.days` / `Recap.models`, pure CSS, no script, the system's light or dark, everything escaped. Mocked up at [design-concept/recap/report.html](../../../../design-concept/recap/report.html) | `Sources/App/UsageHistory/` |
| `ReportSaver` | where a report leaves the app: the save panel (named for the range), the atomic write, the file opened when saved; a failed write is its `failure`, which the card shows. The App's edge, kept thin | `Sources/App/UsageHistory/` |

```
 card appears · usage read (monitor.readToday)
   └─ Recaps.readIfStale()            nothing when the ranges and each login's lastThirtyDays are the ones it read for
        for .this(.week), .last(.week), .this(.month), .last(.month):
          this   = each provider's days(in: range)          ← UsageHistory.days(in:), each distinct range once
          before = each provider's days(in: rangeBefore)
          Recap(range:, this:, before:)
   └─ RecapCardView(recaps:, name:) → the chosen range's recap, its RecapRange's words; an empty range says so, the chips stay
         └─ export button → ReportSaver.save(RecapHTMLReport(recap:, range:, name:)) → save panel → file, opened
                                         a failed write → saver.failure → the card's alert
```

Both ranges of a period are read together, so the chips are there whichever holds
usage, and switching reads nothing. The change's label comes from the same
`RecapRange` the recap was read for, so it always names the range before the
one on screen. The days come from the ledger for closed days and from the logs
only for the open ones (daily-usage), so reading four ranges costs little.

The card is shown while the **Recap** usage section is: `UsageSection`
owns its default (shown), the person's switch in Settings → General overrides
it, and the settings repository keeps the choice. It needs the All page,
which is offered from two providers.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a quarter recap | `RecapPeriod`: a case and the range it names; *before* and every `RecapRange` follow |
| another highlight (a median day, cost per session) | a value built from `Days`, read in `recap.unit` — never a count in the card |
| another tool in the recap | its definition's `usageHistory`; the recap reads whatever days a login has |
| the week to start on Sunday | the person's calendar — no code |
| provider colours from the provider's look | the App: `ModelColors`' hues, or the provider's own; nothing in the kernel |
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
| four flat cases (*thisWeek* … *lastMonth*) and a *isMonth* flag | the period hides as a Bool; *before* switches on case pairs, and a quarter is an edit to every switch |
| a parallel map of each range's dates beside the recaps | two answers to *which dates*; the recap carries its own range |
| the card opening the save panel and writing the file | saving is an OS fact at the App's edge; the view renders and tells |
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
