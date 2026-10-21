---
description: A Weekly Recap card on the popover's All page adds up the week across every provider — cost, tokens, working time, the split by provider, the top model, the biggest day, cache savings, and last week to compare. Use when it is missing or looks off.
---

# Weekly Recap

Once a week it is worth seeing **what all of it added up to**, not just today.
The popover's **All** page shows a **WEEKLY RECAP** card that reads the same
local logs as the daily usage cards, but as a week:

| Line | Shows |
|---|---|
| **The total** | Estimated cost, tokens and working time for the range, added up across every provider |
| **The split** | Each provider's share, largest first — *Claude 62% · Codex 38%* |
| **Top model** | The model that spent the most in the range |
| **Biggest day** | The day that added up to the most |
| **Cache savings** | What prompt caching saved over the range, in dollars |
| **Vs last week** | How the range compares with the one before it |

A range choice at the top switches between **This week** and **Last week**.
*This week* runs from your week's first day (your calendar's, usually Monday)
through today.

## Where it is

The card sits on the **All** page, under the provider overview. The All page is
the one that is already about every provider at once, and the recap is the one
read that adds them up. It needs **two or more providers** to appear, because
that is when the All page is offered.

It is shown only while **Daily Usage Cards** is on — Settings → **General** →
**Daily Usage Cards** — because it reads the same logs, on the same cadence:
when you open the popover, never in the background.

## How the numbers are worked out

- **The days are the same days** the *TODAY'S USAGE* cards and the 30-day
  chart read: your local calendar days, summed from each tool's own logs, with
  duplicates removed. See [daily-usage](../daily-usage/README.md) for how a
  day is built and which tools have logs.
- **Every provider with logs is added up**, and the split says which ones. A
  provider with no logs for the week simply isn't there.
- **Cost is an estimate**, the API list-price value of your usage, not your
  subscription bill — as in the daily cards. A tool whose logs can't be priced
  still counts its tokens, and the week leads with cost whenever any tool can
  be priced.
- **Working time** adds up the stretches between your first and last message,
  a new stretch after a gap of more than 30 minutes.
- **Vs last week** compares the same unit — cost when anything was priced,
  tokens otherwise.

## Gotchas

- **No card at all**: the range holds nothing (no sessions this week, and none
  last week either), Daily Usage Cards is off, or you have only one provider
  and so no All page.
- **The week looks low early on**: *This week* is a week in progress. Compare
  it with *Last week* for a fair picture.
- **Cost is $0 while you were on a local model**: expected — nothing bills you
  per token on your own machine. Tokens still count.
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