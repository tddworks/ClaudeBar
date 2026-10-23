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
                           │     = UsageMix<ModelUsageLine>      the one mix, ByProject its project key
                           │
                           └─► DayActivity(of: days, in: unit)   days: [DayValue] DayValue = date · value · share · busiest

ModelUsageLine = model + Spend          a line is its key and what it spent (UsageLine)
UsageLine + UsageLine                   two lines of one name add their spends
Spend.value(in: unit)                   a spend reads itself in a unit
UsageHeatmap.level(of: DayValue)        the App's shading band, 0…4
```

| Type | Answers | Where |
|---|---|---|
| `Days` | the range: its days, the units it offers, a day's value in a unit, the total, what caching saved, its last `n` days | `Modules/Quotas/Sources/Days.swift` |
| `Spend` | tokens by kind and their cost: `+`, `−`, its value in a unit | `Modules/Quotas/Sources/Spend.swift` |
| `UsageLine` | a line of a day's split, a name and a `Spend` (`ModelUsageLine`, `ProjectUsageLine`); `+` | `Modules/Quotas/Sources/UsageLine.swift` |
| `UsageMix` (`ModelMix`) | each line summed over the range, largest first (ties by name), each `Part` with its value and share; `top`, `names`, `isEmpty` | `Modules/Quotas/Sources/UsageMix.swift` |
| `DayActivity` | every date with its value and its share of the busiest day; `busiest` | `Modules/Quotas/Sources/DayActivity.swift` |
| `DayValue` | one day: date, value, share | `Modules/Quotas/Sources/DayValue.swift` |

**The share is the fact; the band is the page's.** `DayActivity` says how full a
day is. How many squares the legend has, and which square a share falls in, is
a display choice, so `UsageHeatmap.level(of:)` sits beside the legend and the
palette in the App. An **empty day is a value of 0**, never a missing one — the
same law a range keeps about its dates — and a range with nothing used has no
busiest day, so every share is 0.

**A spend owns its sum.** `ModelMix` adds a model's lines with `+`, which adds
their `Spend`s, so a field a day gains is added once, by the spend, never
dropped by a field-by-field copy — for model lines and project lines alike.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a range offers its units and names the one a view opens on; a day's and the range's value in a unit; what caching saved over the range | `Days` |
| what a part spent adds up field by field and reads itself in a unit | `Spend` |
| two lines of one model add up to one line: their spends added | `UsageLine` (`+`) |
| the mix is each model summed over the range, largest first, ties by name, the unnamed line included so the parts add up; each part carries its share; the top model is the largest named one, never the unnamed line | `UsageMix` (`ModelMix`) |
| a day's share is its value against the range's busiest; a range with nothing used has no busiest day, and every share is 0 | `DayActivity` |
| a day's shade is one of five bands by its share; a day with nothing is band 0 — a cell, never a gap | `UsageHeatmap` (App) |
| a value is written once per unit: money for cost, a count for tokens and cache | `UsageFormat` (App), money through `MoneyFormat`, counts, shares and changes through `UsageNumberFormat` (the kernel's, shared with the recap webhook) |
| a day with nothing is an empty day, not a missing one — a series has every date in its range (unchanged) | `UsageHistory.days(in:)` |
| the heatmap (*Last year*) and the mix (*Model mix*) are two usage sections, each hidden until the person shows it; the year is read only while one of them is shown | `UsageSection` (its default, `readsTheYear`) · the settings repository (the person's switch) |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `UsageMix` (`ModelMix`), `DayActivity`, `DayValue` | the two questions, as values | `Modules/Quotas/Sources/` |
| `UsageHistory.lastYear` | the year the insights read, once read and when any day holds usage; `nil` until `readYear()` is asked for; `lastThirtyDays` is its last thirty days | `Modules/Providers/Sources/UsageHistory.swift` |
| `UsageSection` | `.lastYear` and `.modelMix`: whether each shows until the person chooses (both hidden), and that both read the year | `Sources/Domain/Settings/` |
| `AppSettingsRepository.isShown(_:)` | the person's switch per section, `app.usageSections.<section>` ([settings](../../../settings.md)) | `Sources/Domain/Settings/`, `Sources/Infrastructure/Settings/` |
| `UsageInsightsHeatmapView` | the year's cells, GitHub-style, with the year's total and what caching saved | `Sources/App/UsageHistory/` |
| `UsageHeatmap` | the cells laid out a column a week, seven rows a week, and each day's band — pure, so it is tested without a screen | `Sources/App/UsageHistory/` |
| `ModelMixView` | the mix as a bar and a row per model, largest first | `Sources/App/UsageHistory/` |
| `UsageFormat` | a value in a unit, a share — the one spelling of a number on the page | `Sources/App/UsageHistory/` |
| `ModelColors` | one palette, so a model keeps its colour between the chart and the mix | `Sources/App/UsageHistory/` |

When the popover opens, the Monitor tells each login's `UsageHistory.read()`
to read today and the thirty days, and never the year. The year is read only
while a section that shows it is on: the popover's usage area tells the login's
history `readYear()` once per login and switch (`.task(id:)` keyed on the login
and whether a shown section `readsTheYear`), and decides nothing else. Until
then `lastYear` is `nil` — not read, never an empty year. The thirty days come
from the ledger, so the year's read costs little beyond the first. Each card
holds `let unit = days.defaultUnit` and passes it in.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a new question of the days (a median, a trend, a recap) | a new value built from `Days`, reusing `ModelMix` and `DayActivity` where it needs a top model or a busiest day |
| a unit chip on the insights | the view's `unit`, held as state; nothing in the kernel |
| the heatmap's window (a month, a quarter) | the page: another range of `days` |
| a different shade scale | `UsageHeatmap.level(of:)` and its legend — the share is the fact |
| a model's colour | nothing: `ModelColors` is one palette for every view |
| the cost by project | built: [quota-by-project](../quota-by-project/design.md) — the definition names the record's directory, and `ByProject` reads it over `Days` |
| per-session cost | **deferred** — see below |

**Per-session cost is still out.** The project half of this deferred question
is built — [quota-by-project](../quota-by-project/design.md): a definition's
shape names the field of the working directory, and `ByProject` reads it over
`Days`. The session half would need a session id named per record the same
way; until a definition says it, the question stays out rather than guessed.

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

- **The first read of a year.** The first time a year section is shown, a year of
  a login's logs is read (once per login); after that the ledger holds the closed
  days and only the open ones are read. A login whose log is a command or a
  database pays its query the same first time. If that proves slow on a large
  log, the window the page asks for is the knob.
- **The insights' names.** The heatmap and the mix head their cards *LAST YEAR*
  as the chart heads its own *LAST 30 DAYS*; if a page ever asks for another
  range, the heading moves to a parameter the page sets.
