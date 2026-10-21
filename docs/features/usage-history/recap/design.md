# Weekly recap — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> a range of days read back as a week's story. Users: [README.md](README.md).
> The days themselves — where they come from, how they are summed and kept —
> are [daily-usage/design.md](../daily-usage/design.md); comparing days with
> everyone else's is [leaderboard/design.md](../../leaderboard/design.md).
> The laws this applies are [CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them);
> this says how the read runs.

## 1 · What a person asks, and what is true

Once a week a person stops and asks: **what did all of this add up to?**
ClaudeBar already answers *how much did I use, day by day?* — *TODAY'S USAGE*
(today against yesterday) and the *Daily usage — last 30 days* chart — and it
answers *how do my days compare with everyone else's?* — the Leaderboard. It
has no answer for the week itself: what the seven days cost, which tools the
week was spent on, which model did the most, which day was the heaviest, what
prompt caching saved, and whether it was more or less than the week before.

A recap is **a read of a range, told as a few highlights**. It is not a new
source of truth: the days are already there, each login's own
`account.usageHistory?.days(in:)` (CANONICAL §5, `UsageHistory.days(in:)`).
What the recap adds is the *week* as the range, and the one read that adds the
logins up.

```
account.usageHistory?.days(in: .last(2))       → TODAY'S USAGE
account.usageHistory?.days(in: .last(30))      → the chart
account.usageHistory?.days(in: thisWeek)       ┐
account.usageHistory?.days(in: lastWeek)       ┘ → the recap (every login, added up)
```

## 2 · The words

| Word | Means | Not |
|---|---|---|
| **recap** | a read of one range of days, told as its highlights: the total, the split by provider, the top model, the biggest day, the cache savings, and the same range before it | a report that is kept, a new source of days, a quota |
| **range** | the period the recap covers — *this week* or *last week*; a `DateRange` in the person's calendar | the 30 days the chart reads; a board's `today`/`7d`/`30d` period |
| **span** | one provider's days inside the range, the unit the recap adds up | a login — two logins of one provider are one span; a `DailyTokens` row |
| **highlight** | one line of the story: the total, a provider's share, the top model, the biggest day, the savings | a chart, a list of days |
| **the same range before it** | the range one period earlier (last week, for this week), read for the comparison only | a stored history; a second recap |

*Recap* is chosen over *summary* or *report*: a report is read on demand and
kept; a recap is looked back at, once, and is a read. Do not rename it back.

## 3 · The model: `Recap`, a read of a range

A `Recap` is the answer to *what did this range add up to?*, and nothing else.
It is built from **spans** — each provider's days in the range — plus the same
spans one period earlier. Every number it shows is derived from the days; none
is stored anywhere.

```
Recap                                    one range, added up
 ├─ totals : Totals                      THE RANGE'S OWN: cost · tokens · working time · sessions
 ├─ previous : Totals?                   THE SAME RANGE BEFORE IT, for the comparison; nil = unknown
 ├─ providers : [ProviderShare]          THE SPLIT, LARGEST FIRST: id · cost · tokens — "says which providers it spans"
 ├─ topModel : TopModel?                 THE MODEL THAT SPENT THE MOST, when a log named one
 ├─ biggestDay : BiggestDay?             THE DAY THAT ADDED UP TO THE MOST, when any day did
 ├─ cacheSavings : Decimal               WHAT PROMPT CACHING SAVED, summed over the range
 └─ knowsCost : Bool                     WHETHER COST MEANS ANYTHING — cost is the unit when it does, tokens when not

Recap.Totals        cost : Decimal · tokens : Int · workingTime : TimeInterval · sessions : Int
Recap.ProviderShare provider : String (an id, a reference) · cost · tokens
Recap.TopModel      model : String · cost · tokens
Recap.BiggestDay    date : Date · cost · tokens
Recap.Span          provider : String · days : [DailyUsageStat]
```

The unit is the one `Days` already chooses: **cost when a login is priced,
tokens when it is not** (`Days.knowsCost`). A recap knows cost when any span
knows cost, so a Mac with one priced tool and one unpriced one still leads
with dollars, and the cost is what the priced tools spent — an estimate, as
every cost in the feature is.

## 4 · The laws, each on the node that owns it

| Law, in the person's terms | Owner |
|---|---|
| a recap may sum across logins for the person's own total, and **says which providers it spans**; it never puts two logins' days into one login's chart — the per-login `UsageHistory.days(in:)` law is unchanged | `Recap` (its `providers`) |
| a recap is a **read of a range, never stored** — closing the popover loses it; the days are the record | `Recap` |
| a recap with nothing in its range is **not shown**, never shown as zeros | `Recap` (`isEmpty`) |
| a day with nothing is an empty day, not a missing one: every date of the range is asked of every login | `UsageHistory.days(in:)` (unchanged) |
| **repo names leave the Mac only when the person says so** — the recap is read and drawn on this Mac, and nothing it holds is sent anywhere | `Recap` · the share view (deferred, §8) |
| cost is the unit when a login is priced, tokens when it is not | `Recap.knowsCost`, from `Days.knowsCost` |

The first law is the one this feature exists to add. It is deliberately narrow:
**summing across logins is allowed here, for the person's total, and only
here.** A login's own chart, cards and days stay that login's — the recap is
the one place the person's whole week is one number, and it names the
providers it covers so the sum is never a mystery.

## 5 · Where it lives

No new module, no new capability, no change to `Provider` or `Monitor`. The
recap is a value in the kernel and a read the App makes.

| Piece | Job | From |
|---|---|---|
| `Recap` (`Quotas/Sources/Recap.swift`) | the value: adds the spans up, names the providers, finds the top model and the biggest day, sums the savings, answers the comparison and the formatted strings | — (new) |
| `RecapBuilder` (`App/UsageHistory/RecapBuilder.swift`) | **pure**: turns each login's days into the spans and builds the `Recap`; it spans logins the Monitor holds, and decides nothing about where they came from | — (new) |
| `RecapCardView` (`App/UsageHistory/RecapCardView.swift`) | the popover card: a range choice (*This week* / *Last week*), the highlights, and the read that fills them; it renders what `Recap` says and never counts | — (new) |
| `RecapRange` (`App/UsageHistory/`) | the page's own choice of range: *this week* / *last week*, and the `DateRange` each names in the person's calendar | — (new) |
| the All page (`MenuContentView`) | hosts the card, under the provider overview — the one page that is already about every provider at once | `OverviewPageView` |
| `DateRange` (`Quotas`) | extended: `before(calendar:)` names the same run of days one period earlier, so *last week* and the comparison are one arithmetic; the range itself is still the caller's cut | — |

`Recap` imports nothing but `Foundation`, like `Days`. `RecapBuilder` is in the
App because it is the one read that **spans logins**, and a login is the
Providers context's — the kernel never learns the word. The App gathers each
login's days through `account.usageHistory?.days(in:)`, exactly as *TODAY'S
USAGE* does, and hands them to the builder.

```
 MenuContentView (All page)
   └─ RecapCardView(monitor: monitor, calendar:)
        │  .task(range)  ──▶  each login: account.usageHistory?.days(in: range)
        │                     each login: account.usageHistory?.days(in: range before it)
        ▼
     RecapBuilder.build(logins, previous:, knowsCost:)   ← pure
        ▼
     Recap(spans:previous:knowsCost:)                    ← adds up, names, finds
        ▼
     the card renders totals · split · top model · biggest day · savings · change
```

The card is shown only while **Daily Usage Cards** is on (Settings → General):
the recap reads the same local logs as the cards, on the same cadence — when
the popover opens, never in the background (CANONICAL §5, `UsageHistory`).

## 6 · The flows

```
 A person opens the popover on All
   └─ the card asks this week's days of every login, and last week's
        └─ days come from each login's ledger and logs (daily-usage §3)
   └─ the recap adds the logins up, names the providers, finds the top model
      and the biggest day, and compares the week with the one before
   └─ the card draws the highlights, or nothing at all when the range is empty

 A person picks Last week
   └─ the card asks last week's days, and the week before that, and draws again
```

## 7 · Is it easy to change? The checks

| A person or a contributor wants… | They change |
|---|---|
| a *month* recap, a *today* recap | `RecapRange`: another case and the `DateRange` it names |
| a different highlight (cost per session, a per-login split) | `Recap` (the value) and the card's one row — the days are already there |
| the recap for one provider only | the card: read that provider's logins instead of `monitor.lineup` |
| another tool to appear in the recap | its definition's `usageHistory` — the recap reads whatever the days hold |
| the week to start on another day | the person's calendar (`Calendar.firstWeekday`) — no code |

## 8 · Considered and rejected

| Considered | Rejected because |
|---|---|
| a new module for the recap | it has no SDK, no second consumer and no boundary to enforce; it is a value in the kernel and a read in the App, as *TODAY'S USAGE* is |
| a `Recap` that keeps its own copy of the days, or a stored weekly report | the days are already the record; a kept recap would be a second source of truth to keep in step with the ledger |
| summing every login's days into one chart on the provider page | the per-login law: a chart is one login's. The recap is a *read*, not a chart, and names the providers it spans |
| a recap for every provider, on its own page | the person's question is about *all of it*; a provider's week is its own *TODAY'S USAGE* and chart |
| a range choice of *today / 7 days / 30 days* | the Leaderboard's periods; the recap's question is the week, and the chart already covers 30 days |
| a `RecapViewModel` that reads the logins | no ViewModel layer: the card reads the domain directly, and the arithmetic is `Recap`'s |

## 9 · Deferred, and open

**Deferred from this slice** (the design keeps them; the code does not yet):

- **The shareable image.** A `RankCard`-style image of the week — the total,
  the split, the top model — drawn on this Mac and saved only when the person
  asks. It is the one surface where repo names could leave the Mac, so it goes
  through the same *"exactly what gets shared"* step the Leaderboard's
  *Share my rank* does. Law: **repo names leave the Mac only when the person
  says so** (`Recap` · the share view).
- **The Monday notification.** A destination (`RecapAnnouncement`), beside
  Notify! and the quota alerts, that says the week is ready once, on the
  person's first look after the week turns. It follows the alerting design:
  a destination, not a provider, and never a Monitor edit.

**Open:**

- **Where the recap lives on a one-provider Mac.** The All page needs two
  providers, so a person with one provider never sees the card. Should the
  recap also sit under *TODAY'S USAGE* on a provider page, or should the All
  page be offered for one provider too?
- **This week is partial.** *This week* runs from the week's first day through
  today; the days still to come are empty, as every range's future days are.
  Whether the card should say *so far* is a wording question, not a model one.
- **Which providers the sum covers.** The recap spans the logins the popover
  watches (`monitor.lineup`). Whether it should follow the *Leaderboard*
  membership's sharing choice — which is a different, explicit choice — is
  open; today it is simply everything on this Mac that has days.