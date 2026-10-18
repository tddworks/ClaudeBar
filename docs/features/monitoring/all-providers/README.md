---
description: See every provider's quota at once in the popover's All tab — a card each with the quota that runs out first, or a row of bars per quota. Use when choosing which assistant to keep working with, or to make the popover open on All.
---

# All providers

The **All** pill, first in the popover's pill row, shows every provider you use on one page: a card each, led by the quota that runs out first — or, if you prefer, a row per provider with a bar per quota. Click a card or a row to open that provider's full page.

```
 [▦ All] [🏆 Leaderboard] ┃ [Claude] [Codex] [Gemini] …
```

## Quick start

1. Open the popover and click **All**, or press **⌘0**.
2. Read the cards: the ring is the quota with the least left, the row under it is the next one.
3. Click a card to see that provider's full page. **All** or **⌘0** brings you back.

## What a card shows

| Part | Shows |
|---|---|
| Ring | the quota with the least left, coloured by its status |
| Rows | that quota and the next lowest, with when they reset |
| Badge | the provider's status. A provider with no numbers says *Unavailable*, *Not set up* or *Syncing*, so it never disappears |
| *N accounts* | with several accounts, the ring is the account that runs out first, named in its row |

The counts above the cards (*1 critical · 1 warning · 3 healthy*) and the header's badge cover every provider. Cards keep your order from **Settings → Providers**.

Cost, today's usage and the 30-day chart stay on each provider's page.

## Open on All every time

**Settings → General → Open On**:

| Choice | The popover opens on |
|---|---|
| **Where I Left It** (default) | the page it was on, All, the Leaderboard or a provider |
| **All** | All, every time |

It's stored as `app.popoverOpensOn` in `~/.claudebar/settings.json` ([settings](../../../settings.md)).

## Read the All page as bars

**Settings → General → All Page Style**:

| Choice | Each provider reads as |
|---|---|
| **Rings** (default) | a card led by the quota that runs out first, the next one under it |
| **Bars** | a row with a bar per quota it watches, so you can read two providers against each other |

Rings answer *which provider can I keep working with?* Bars answer *how much room do I have on each window?* — a card shows one provider's tightest quota, so a provider with three or more quotas is cut to two, and two rings compare different windows.

In **Bars** each row is a provider, in your pill order, and each line is one of its quotas:

- Lines are ordered by the window the provider states, **shortest first**. Most
  providers don't state windows, so their lines simply read tightest first;
  the ones that do (a session against a weekly, say) line up in one column.
- Every bar starts and ends in the same place on the page, so two percentages can be compared directly.
- A line shows the quota's name, its reset countdown, its percentage in your **Quota Display** mode, and a pace tick where that applies.
- Only the quotas you watch appear — hide one in **Settings → Providers** and it disappears here too.
- A provider with no numbers keeps its row and its word (*Unavailable*, *Not set up*, *Syncing*). A prepaid balance has no ceiling, so it shows its amount, not a bar.
- Clicking a row opens that provider's page, exactly as a card does.

It's stored as `app.allPageStyle` in `~/.claudebar/settings.json` ([settings](../../../settings.md)).

## Good to know

- All shows only when two or more providers are on. With one, the popover shows that provider.
- All replaces **Overview Mode**. If you had it on, the popover opens on All after the update. Bars is not Overview Mode brought back — it prints the quotas, not each provider's whole page.
- The menu bar keeps showing the provider you last picked; All doesn't change it.
- With many providers, bars scroll more than rings do, which is why rings are the default.
