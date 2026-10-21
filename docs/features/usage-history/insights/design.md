# Usage insights — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). The days it reads, and
> how a login's logs become them: [daily-usage](../daily-usage/design.md).

> **Status: BUILT.** Mockup: [design-concept/usage-insights](../../../../design-concept/usage-insights/index.html).

## 1 · What a person asks, and what is true

Tom ([USER_JOURNEYS §1](../../../architecture/USER_JOURNEYS.md)) asks **"what did
I use, day by day?"** — and, once the days are there, **"what does the shape of
it say?"**: the year at a glance, a streak of days under his own ceiling, which
models he actually leans on, how much the cache saved.

Every one of those is a question asked of a **range of days**. So every one is
answered where `Days` is (CANONICAL §5, `Days`), and a view renders what it says
and tells — it never counts, compares or divides for itself. This feature adds
**reads to `Days`** and one value beside it; it adds no new source, no store and
no fetch. The days are the ones [daily-usage](../daily-usage/design.md) already
reads:

```swift
let year = account.usageHistory?.days(in: .last(365))   // the heatmap and the mix
let days = year                                        // …and every question is asked of it
days.byDay                                             // a cell a day: its value and its shade
days.byModel                                           // the mix, largest first
days.total(in: .cost)                                  // the range in a unit
days.cacheSavings                                      // what caching saved
Streak(of: days, under: .atMost(20))                   // days under a ceiling
```

## 2 · The words

| Word | Means |
|---|---|
| a **range** | the days a page asks for — `days(in:)`; the insights read a year |
| the **unit** | what a range is read in: cost when the login is priced, tokens when it isn't (`Days.knowsCost`) |
| a **day's value** | a day's number in the unit — a bar's height |
| a **day's shade** | how full a day is against the range's busiest — the heatmap's cell |
| the **mix** | one line per model over the range, largest first, the unnamed line among them so the mix adds up |
| a **streak** | the most recent days of a range, each under a ceiling the person set |
| a **breach** | a day above the ceiling; an empty day is never one |

The unnamed line is the records a log writes with no model. It is not a model
(`Days.models` leaves it out), but it is part of the mix and part of a day, so
the mix adds up to the range exactly as a day's lines add up to the day.

## 3 · The model: `Days` grows the reads a view needs

`Days` keeps every law it had — which models, in order; a day's lines, largest
first; its total in a unit — and gains only what the new questions need. Each
read has **one owner**, `Days` itself.

| Read | Answers | The view that asks |
|---|---|---|
| `unit` | what a range is read in now | every card's caption |
| `total(in: Unit)` | the range in a unit — cost, tokens or working time | a headline, a year's total |
| `byDay → [DayValue]` | a day and its value in the unit, and its shade | the heatmap |
| `byModel → [ModelUsageLine]` | the mix: each model summed over the range, largest first | the model mix |
| `share(of: ModelUsageLine)` | one model's part of the range, 0…1 | the model mix's percentage |
| `cacheSavings` | what caching saved over the range | the heatmap's caption |

`total` stays, and is `total(in: unit)`: the unit in force, unchanged, so every
existing caller reads the same number. `byDay` and `byModel` are read in the
unit in force, so an unpriced login's insights are tokens, never a made-up $0 —
the same rule a day's total already keeps.

**A `DayValue`** is one day's number and its shade:

```swift
public struct DayValue: Sendable, Equatable {
    public let date: Date
    public let value: Double    // in the unit in force
    public let share: Double    // 0…1 against the range's busiest day
    public var level: Int       // 0 for a day with nothing, else 1…4 by share
}
```

The **shade** is a fact about the range, not a colour: *how full is this day
against the busiest one here*. `Days` owns it, so a heatmap never finds a
maximum or picks a band; it maps `level` to its palette, which is the page's.
An **empty day is a cell with level 0**, never a missing one — the same law a
range keeps about its dates (CANONICAL §5, *a day with nothing is an empty day,
not a missing one*). A range with nothing in it has no busiest day, so every
day is level 0.

**A `Streak`** is a run of days under a ceiling:

```swift
public struct Streak: Sendable, Equatable {
    public enum Threshold: Sendable, Equatable {
        case atMost(Double)   // a daily budget, in the unit in force
        case share(Double)    // at most this share of the range's busiest day
    }
    public let length: Int        // how many of the range's last days held
    public let daysInRange: Int   // how many days the range holds
    public let threshold: Threshold
    public var isWholeRange: Bool // the run is the whole range
}
```

It is counted **back from the range's last day** — the streak the person is on
now — and stops at the first day that breaches. **An empty day is not a
breach**: a day with nothing used is under any ceiling, so a quiet weekend does
not end a streak. `.atMost` is the person's own ceiling (a daily budget) in the
unit in force; `.share` needs no budget at all — *at most half my busiest day* —
so the value is useful before any budget is wired.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a range of days answers the page's questions — which models, in order; a day's lines, largest first; its total in a unit; **the mix, largest first; a day's value and its shade; what the cache saved** — so a view renders and tells | `Days` |
| a day's shade is how full it is against the range's busiest; a day with nothing is level 0 — a cell, never a gap | `DayValue` |
| a streak is the range's most recent days, each under the ceiling, and stops at the first breach; an empty day is not a breach | `Streak` |
| a range read in tokens (an unpriced login) answers the insights in tokens, never a made-up $0 | `Days.unit` |
| a day is the local calendar day; a record counts on the day its own timestamp falls in (unchanged) | `Day` |
| a day with nothing is an empty day, not a missing one — a series has every date in its range (unchanged) | `UsageHistory.days(in:)` |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `Days` (grows) | `unit` · `total(in:)` · `byDay` · `byModel` · `share(of:)` · `cacheSavings` | `Modules/Quotas/Sources/Days.swift` |
| `DayValue` | a day's value in a unit and its shade | `Modules/Quotas/Sources/DayValue.swift` |
| `Streak` | the most recent days under a ceiling | `Modules/Quotas/Sources/Streak.swift` |
| `UsageHistory.lastYear` | the year the insights read, once read and when any day holds usage | `Modules/Providers/Sources/UsageHistory.swift` |
| `UsageInsightsHeatmapView` | the year's cells, GitHub-style, with the year's total and what caching saved | `Sources/App/UsageHistory/` |
| `UsageHeatmap` | the cells laid out a column a week, seven rows a week — pure, so it is tested without a screen | `Sources/App/UsageHistory/` |
| `ModelMixView` | the mix as a bar and a row per model, largest first | `Sources/App/UsageHistory/` |
| `ModelColors` | one palette, so a model keeps its colour between the chart and the mix | `Sources/App/UsageHistory/` |

The heatmap and the mix **read the year**, so `UsageHistory` reads one more
range beside the two it already reads — the cards' two days and the chart's
thirty — and the page places them under the chart. Nothing else moves: the
insights are the same login's days, read at the same moment (the popover opens,
never the background).

`UsageHeatmap` is a value, not a view: it turns `Days.byDay` into the columns a
GitHub-style heatmap draws, so "every date is a cell" and "an empty day is a
cell, not a gap" are tested as state, with no screen in the loop.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a new question of the days (a median, a trend) | a read on `Days`, and its test |
| the heatmap's window (a month, a quarter) | the page: another range of `days` |
| the streak shown, once a daily budget is wired | the page: `Streak(of: days, under: .atMost(budget))` |
| a different shade scale | the heatmap's palette (the page's) — `DayValue.level` is the fact |
| a model's colour | nothing: `ModelColors` is one palette for every view |
| per-repo or per-session cost | **deferred** — see below |

**Per-repo and per-session cost is deliberately out of this slice.** It needs a
repo (or a session id) named **per record**, and the log's definition may not
carry one: Claude's assistant lines name a model and a request, not a repo, so
the repo would have to be inferred from a file path or a session's first
prompt — a new field in the mapping's path language, not a read on `Days`. Until
a definition can say *which repo this record is*, the question is unanswerable
and is left out rather than guessed.

## 7 · Considered and rejected

- **Arithmetic in the views.** A heatmap that finds its own maximum, or a mix
  that divides its own shares, puts the answer in the screen and the law in two
  places. The reads live on `Days`; the views render.
- **An `Insights` aggregate.** A second type over the same days would own the
  same laws twice, and the page would ask two objects the same question. `Days`
  is the range; the insights are questions asked of it.
- **Colours in `DayValue`.** A shade is how full a day is; the colour is the
  page's, like every other colour in the popover. `level` is the fact, the
  palette is the App's.
- **A `Streak` of the longest run.** The person asks *am I on a streak*, not
  *what was my best one*; the longest run is a different question, added when a
  screen asks it.
- **Reading the year on every open.** The closed days are kept by the
  `DayLedger`, and the JSON-lines reader keeps what it already parsed, so only
  the first read of a year pays for it. See §8.

## 8 · Open

- **The first read of a year.** The first time the insights are shown, a year of
  a login's logs is read (once per login); after that the ledger holds the closed
  days and only the open ones are read. A login whose log is a command or a
  database (OpenCode) pays its query the same first time. If that proves slow on
  a large log, the window the page asks for is the knob — a quarter, or a year
  read on demand.
- **The streak's surface.** No screen shows a `Streak` yet: it needs the login's
  daily budget (`account.budget`, CANONICAL §2.1), which is a separate change.
  The value and its tests land here so the surface is a one-line change.
- **The insights' names.** The heatmap and the mix head their cards *LAST YEAR*
  as the chart heads its own *LAST 30 DAYS*; if a page ever asks for another
  range, the heading moves to a parameter the page sets.