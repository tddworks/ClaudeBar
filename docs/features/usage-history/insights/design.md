# Usage insights — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). The days it reads, and
> how a login's logs become them: [daily-usage](../daily-usage/design.md).

> **Status: BUILT.** Mockup: [design-concept/usage-insights](../../../../design-concept/usage-insights/index.html).

## 1 · What a person asks, and what is true

Tom ([USER_JOURNEYS §1](../../../architecture/USER_JOURNEYS.md)) asks **"what did
I use, day by day?"** — and, once the days are there, **"what does the shape of
it say?"**: the year at a glance, which models he actually leans on, how much
the cache saved.

Each of those is a question asked of a **range of days**, and each question the
person names is **its own small value built from `Days`**, holding its data and
its rule together. `Days` stays the range; it does not grow a read per page. A
view holds the unit, passes it in, and renders what the value says — it never
counts, compares or divides for itself. The feature adds no new source, no store
and no fetch; the days are the ones [daily-usage](../daily-usage/design.md)
already reads:

```swift
let year = account.usageHistory?.lastYear               // the range
let unit = year.defaultUnit                             // the view's one choice
ModelMix(of: year, in: unit).parts                      // "which models do I lean on"
DayActivity(of: year, in: unit).days                    // "what does my year look like"
year.total(in: unit)                                    // the range in a unit
year.cacheSavings                                       // what caching saved
```

## 2 · The words

| Word | Means |
|---|---|
| a **range** | the days a page asks for — `Days`; the insights read a year |
| the **unit** | what a range is read in — cost, tokens or cache. The range offers it (`Days.units`) and names the one a view opens on (`Days.defaultUnit`); the view picks |
| a **day's value** | a day's number in the unit |
| a day's **share** | how full a day is against the range's busiest, 0…1 |
| the **busiest day** | the day used most; a range with nothing used has none |
| the **mix** | one part per model over the range, largest first, the unnamed line among them so the parts add up |
| a **shade** | one of the heatmap's five bands for a day's share — the App's, beside its legend |

The unnamed line is the records a log writes with no model. It is not a model
(`Days.models` leaves it out), but it is a part of the mix and of a day, so the
mix adds up to the range exactly as a day's lines add up to the day.

## 3 · The model: one value per question

```
UsageHistory.lastYear ──► Days   (the range: stats · units · defaultUnit · value(of:in:) · total(in:) · cacheSavings · last(n))
                           │
                           ├─► ModelMix(of: days, in: unit)      parts: [Part]   Part = line · value · share   · top
                           │
                           └─► DayActivity(of: days, in: unit)   days: [DayValue] DayValue = date · value · share · busiest

ModelUsageLine + ModelUsageLine         a line owns its own sum
UsageHeatmap.level(of: DayValue)        the App's shading band, 0…4
```

| Type | Answers | Where |
|---|---|---|
| `Days` | the range: its days, the units it offers, a day's or a line's value in a unit, the total, what caching saved, its last `n` days | `Modules/Quotas/Sources/Days.swift` |
| `ModelUsageLine` `+` | two lines of one model as one: every count and the cost added | `Modules/Quotas/Sources/ModelUsageLine.swift` |
| `ModelMix` | each model summed over the range, largest first (ties by name), each `Part` with its value and share; `top` | `Modules/Quotas/Sources/ModelMix.swift` |
| `DayActivity` | every date with its value and its share of the busiest day; `busiest` | `Modules/Quotas/Sources/DayActivity.swift` |
| `DayValue` | one day: date, value, share | `Modules/Quotas/Sources/DayValue.swift` |

**The share is the fact; the band is the page's.** `DayActivity` says how full a
day is. How many squares the legend has, and which square a share falls in, is
a display choice, so `UsageHeatmap.level(of:)` sits beside the legend and the
palette in the App. An **empty day is a value of 0**, never a missing one — the
same law a range keeps about its dates — and a range with nothing used has no
busiest day, so every share is 0.

**A line owns its sum.** `ModelMix` adds a model's lines with `+`, so a field a
day gains is added by the line itself, never dropped by a field-by-field copy.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a range offers its units and names the one a view opens on; a day's, a line's and the range's value in a unit; what caching saved over the range | `Days` |
| two lines of one model add up to one line: every count and the cost | `ModelUsageLine` (`+`) |
| the mix is each model summed over the range, largest first, ties by name, the unnamed line included so the parts add up; each part carries its share | `ModelMix` |
| a day's share is its value against the range's busiest; a range with nothing used has no busiest day, and every share is 0 | `DayActivity` |
| a day's shade is one of five bands by its share; a day with nothing is band 0 — a cell, never a gap | `UsageHeatmap` (App) |
| a value is written once per unit: money for cost, a count for tokens and cache | `UsageFormat` (App), money through `MoneyFormat` |
| a day with nothing is an empty day, not a missing one — a series has every date in its range (unchanged) | `UsageHistory.days(in:)` |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `ModelMix`, `DayActivity`, `DayValue` | the two questions, as values | `Modules/Quotas/Sources/` |
| `UsageHistory.lastYear` | the year the insights read, once read and when any day holds usage; `lastThirtyDays` is its last thirty days | `Modules/Providers/Sources/UsageHistory.swift` |
| `UsageInsightsHeatmapView` | the year's cells, GitHub-style, with the year's total and what caching saved | `Sources/App/UsageHistory/` |
| `UsageHeatmap` | the cells laid out a column a week, seven rows a week, and each day's band — pure, so it is tested without a screen | `Sources/App/UsageHistory/` |
| `ModelMixView` | the mix as a bar and a row per model, largest first | `Sources/App/UsageHistory/` |
| `UsageFormat` | a value in a unit, a share — the one spelling of a number on the page | `Sources/App/UsageHistory/` |
| `ModelColors` | one palette, so a model keeps its colour between the chart and the mix | `Sources/App/UsageHistory/` |

`UsageHistory` reads the year once when the popover opens; the chart's thirty
days are the year's tail (`Days.last(30)`), so the logs are never read twice for
one open. Each card holds `let unit = days.defaultUnit` and passes it in.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a new question of the days (a median, a trend, a recap) | a new value built from `Days`, reusing `ModelMix` and `DayActivity` where it needs a top model or a busiest day |
| a unit chip on the insights | the view's `unit`, held as state; nothing in the kernel |
| the heatmap's window (a month, a quarter) | the page: another range of `days` |
| a different shade scale | `UsageHeatmap.level(of:)` and its legend — the share is the fact |
| a model's colour | nothing: `ModelColors` is one palette for every view |
| per-repo or per-session cost | **deferred** — see below |

**Per-repo and per-session cost is out of this feature.** It needs a repo (or a
session id) named **per record**, and a log's definition may not carry one: a
log may name a model and a request, not a repo, so the repo would have to be
inferred from a file path or a session's first prompt — a new field in the
mapping's path language, not a value over `Days`. Until a definition can say
*which repo this record is*, the question is left out rather than guessed.

## 7 · Considered and rejected

- **Every read on `Days`.** One type would change for every new page — how
  models are ranked, how busy a day is, how money is shown. Each question is its
  own value instead.
- **Arithmetic in the views.** A heatmap that finds its own maximum, or a mix
  that divides its own shares, puts the law in the screen. The values compute;
  the views render.
- **A shading band in the kernel.** Five squares is a legend's choice; the
  kernel says how full a day is.
- **A streak.** No screen shows one; it is added with the feature that does.
- **Reading the year on every open.** The closed days are kept by the
  `DayLedger`, and the JSON-lines reader keeps what it already parsed, so only
  the first read of a year pays for it. See §8.

## 8 · Open

- **The first read of a year.** The first time the insights are shown, a year of
  a login's logs is read (once per login); after that the ledger holds the closed
  days and only the open ones are read. A login whose log is a command or a
  database pays its query the same first time. If that proves slow on a large
  log, the window the page asks for is the knob.
- **The insights' names.** The heatmap and the mix head their cards *LAST YEAR*
  as the chart heads its own *LAST 30 DAYS*; if a page ever asks for another
  range, the heading moves to a parameter the page sets.
