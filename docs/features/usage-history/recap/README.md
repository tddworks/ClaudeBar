---
description: A Recap card on the popover's All page adds up the week or month across every provider — total, split, top model, biggest day, cache savings, against the range before — and exports as a self-contained HTML report. Use when it is missing or looks off.
---

# Recap

Once a week — or a month — it is worth seeing **what all of it added up to**,
not just today. The popover's **All** page shows a **RECAP** card that reads
the same local logs as the daily usage cards, but as a whole range:

| Line | Shows |
|---|---|
| **The total** | The week or month across every provider — estimated cost, or tokens when a provider's logs can't be priced — with the tokens, working time and sessions beside it |
| **The split** | Each provider's total and share, largest first — *Claude 62% · Codex 38%* |
| **Top model** | The model that did the most in the range, across every provider |
| **Biggest day** | The day that added up to the most, written in your own language |
| **Cache savings** | What prompt caching saved over the range, in dollars |
| **Vs the range before** | How the range compares with the one before it — *vs last week*, *vs the month before*, and so on for the range chosen |

A range choice at the top switches between **This week**, **Last week**,
**This month** and **Last month**. *This week* runs from your week's first day
(your calendar's, usually Monday) through today; *this month* is your
calendar's month. The card appears as soon as **any** range has usage, and a
range with nothing says *Nothing this week* (and so on) instead of vanishing —
so the choice is always there to switch with.

## Take it with you — the HTML report

The export button (top right of the card) writes the recap you are looking at
out as **one HTML file** — styled on its own, in light or dark to match the
reader's system, with nothing to install and nothing fetched from the network.
Pick where to save it; the file opens in your browser when saved, and if it
can't be written the card says why. The app never reads it back.

It carries the card's numbers and then the detail the card only summarises:

| In the report | What it says |
|---|---|
| **The week / month** | the total, the change, tokens, time worked, sessions |
| **Day by day** | a bar for every day; point at one for that day's cost, tokens, sessions, time worked, cache savings and top models |
| **Hour by hour** | a row for every day and a cell for every hour, shaded by what that hour spent — when in the day you work; the **All** row adds the days up. Point at a cell for that hour in every unit, click a row to pick its day |
| **Where it went · Models · Projects** | a row for every provider, every named model and every named project, each with its value, its share and its change against the period before |
| **Tokens by kind** | input, output, cache writes and cache reads |
| **Highlights** | top model, biggest day, active days, the average per active day and per session, what the cache saved and its hit rate |

And you can ask it things:

- **Cost · Tokens · Cache** (top right) reads the whole page in another unit.
  Dollars are offered only when the recap itself reads in dollars.
- **Total · Provider · Model · Project** stacks each day's bar by that split.
- **Click a day** and every list below reads for that day alone; click it
  again, or *Show the whole week*, to go back.
- **Sort** a list by name, value or change; a long list shows its first eight
  rows and *Show all*.

If the reader's browser runs no script (some mail previews don't), the page
still says the whole recap in the unit the card used — only the choices are
gone.

## Where it is

The card sits on the **All** page, under the provider overview. The All page is
the one that is already about every provider at once, and the recap is the one
read that adds them up. It needs **two or more providers** to appear, because
that is when the All page is offered.

It is **on by default**; turn it off or on in Settings → **General** →
**Usage in the popover** → **Recap**. It reads the same logs as the
daily cards, on the same cadence: when you open the popover, never in the
background.

## How the numbers are worked out

- **The days are the same days** the *TODAY'S USAGE* cards and the 30-day
  chart read: your local calendar days, summed from each tool's own logs, with
  duplicates removed. See [daily-usage](../daily-usage/README.md) for how a
  day is built and which tools have logs.
- **Every provider with logs is added up**, and the split says which ones. A
  provider with no logs for the range simply isn't there.
- **Cost is an estimate**, the API list-price value of your usage, not your
  subscription bill — as in the daily cards.
- **One unit for the whole card.** The recap reads in dollars only when every
  provider you used in the range or the one before can be priced. If one can't
  (OpenCode Go, a local model), the whole card — total, split, top model,
  biggest day and change — reads in **tokens**, so nothing counts as $0.
- **Tokens are the chart's tokens**: input and output. Cache reads and writes
  are not added in.
- **Working time** adds up the stretches between your first and last message,
  a new stretch after a gap of more than 30 minutes.
- **Vs the range before** compares the same unit, and is left out when nothing
  was used the range before. A month is compared with the month before it —
  months differ in length, so a month steps a month, never a fixed 30 days.
- **It follows your usage**: the card reads again when the week or the month
  turns, or when the popover reads your logs again.

## Gotchas

- **A day says *no hours kept for this day***: ClaudeBar began keeping hours
  with this version. A past day whose tool has since cleared its logs keeps its
  totals but can't say when they were spent. The same row shows when one of
  several providers can't say — half a day's hours would read as the whole
  day's.
- **No *Hour by hour* section at all**: no day of the range knows its hours
  yet. Open the popover once after updating; days whose logs still exist are
  read again.

- **No card at all**: nothing in *any* range (no sessions this week, last
  week, this month or last month), **Recap** is off, or you have only one
  provider and so no All page. One empty range on its own still shows the
  card.
- **The range looks low early on**: *This week* and *This month* are ranges in
  progress. Compare them with the last full one for a fair picture.
- **The card reads in tokens, not dollars**: one provider you used in the
  range or the one before prices nothing. Expected — a sum in dollars would
  count it as $0.
- **A second login of the same provider is added in**, not shown apart: the
  split is by provider, so *Personal* and *Work* Claude read as one **Claude**.
- **Nothing leaves the Mac by itself.** The recap is read and drawn here. The
  HTML report goes only where *you* save it, and holds what the card shows
  plus the detail behind it — provider, model and **project names** (a
  project is the folder's name, never its path) among them — so send it only
  to people who may read those. The recap itself travels out only if you tick **Weekly
  recap** on a [webhook](../../alerting/webhooks/README.md). The shareable
  image and a Mac notification of its own are not built.

## See also

[daily-usage](../daily-usage/README.md) — the days the recap reads ·
[design.md](design.md) — how the read runs, and its laws ·
[leaderboard](../../leaderboard/README.md) — comparing days with everyone
else's · [all-providers](../../monitoring/all-providers/README.md) — the All
page
