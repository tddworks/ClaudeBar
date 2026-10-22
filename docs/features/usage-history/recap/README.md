---
description: A Weekly Recap card on the popover's All page adds up the week across every provider — the total in dollars or tokens, the split by provider, the top model, the biggest day, cache savings, against the week before. Use when it is missing or looks off.
---

# Weekly Recap

Once a week it is worth seeing **what all of it added up to**, not just today.
The popover's **All** page shows a **WEEKLY RECAP** card that reads the same
local logs as the daily usage cards, but as a week:

| Line | Shows |
|---|---|
| **The total** | The week across every provider — estimated cost, or tokens when a provider's logs can't be priced — with the tokens, working time and sessions beside it |
| **The split** | Each provider's total and share, largest first — *Claude 62% · Codex 38%* |
| **Top model** | The model that did the most in the week, across every provider |
| **Biggest day** | The day that added up to the most, written in your own language |
| **Cache savings** | What prompt caching saved over the range, in dollars |
| **Vs the week before** | How the range compares with the one before it — *vs last week*, or *vs the week before* when *Last week* is chosen |

A range choice at the top switches between **This week** and **Last week**.
*This week* runs from your week's first day (your calendar's, usually Monday)
through today. The card appears as soon as **either** week has usage, and a
week with nothing says *Nothing this week* (or *Nothing last week*) instead of
vanishing — so the choice is always there to switch with.

## Where it is

The card sits on the **All** page, under the provider overview. The All page is
the one that is already about every provider at once, and the recap is the one
read that adds them up. It needs **two or more providers** to appear, because
that is when the All page is offered.

It is **on by default**; turn it off or on in Settings → **General** →
**Usage in the popover** → **Weekly recap**. It reads the same logs as the
daily cards, on the same cadence: when you open the popover, never in the
background.

## How the numbers are worked out

- **The days are the same days** the *TODAY'S USAGE* cards and the 30-day
  chart read: your local calendar days, summed from each tool's own logs, with
  duplicates removed. See [daily-usage](../daily-usage/README.md) for how a
  day is built and which tools have logs.
- **Every provider with logs is added up**, and the split says which ones. A
  provider with no logs for the week simply isn't there.
- **Cost is an estimate**, the API list-price value of your usage, not your
  subscription bill — as in the daily cards.
- **One unit for the whole card.** The recap reads in dollars only when every
  provider you used this week or last can be priced. If one can't (OpenCode
  Go, a local model), the whole card — total, split, top model, biggest day
  and change — reads in **tokens**, so nothing counts as $0.
- **Tokens are the chart's tokens**: input and output. Cache reads and writes
  are not added in.
- **Working time** adds up the stretches between your first and last message,
  a new stretch after a gap of more than 30 minutes.
- **Vs the week before** compares the same unit, and is left out when nothing
  was used the week before.
- **It follows your usage**: the card reads again when the week turns or when
  the popover reads your logs again.

## Gotchas

- **No card at all**: nothing in *either* week (no sessions this week and none
  last week), **Weekly recap** is off, or you have only one provider and so
  no All page. One empty week on its own still shows the card.
- **The week looks low early on**: *This week* is a week in progress. Compare
  it with *Last week* for a fair picture.
- **The card reads in tokens, not dollars**: one provider you used this week or
  last prices nothing. Expected — a sum in dollars would count it as $0.
- **A second login of the same provider is added in**, not shown apart: the
  split is by provider, so *Personal* and *Work* Claude read as one **Claude**.
- **Nothing leaves the Mac.** The recap is read and drawn here; the shareable
  image and the Monday notification are not built yet.

## See also

[daily-usage](../daily-usage/README.md) — the days the recap reads ·
[design.md](design.md) — how the read runs, and its laws ·
[leaderboard](../../leaderboard/README.md) — comparing days with everyone
else's · [all-providers](../../monitoring/all-providers/README.md) — the All
page