---
description: See every provider's quota at once in the popover's All tab, one card each with the quota that runs out first. Use when choosing which assistant to keep working with, or to make the popover open on All.
---

# All providers

The **All** pill, first in the popover's pill row, shows every provider you use on one page: a card each, led by the quota that runs out first. Click a card to open that provider's full page.

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

It's stored as `app.popoverOpensOn` in `~/.claudebar/settings.json` ([settings](../../settings.md)).

## Good to know

- All shows only when two or more providers are on. With one, the popover shows that provider.
- All replaces **Overview Mode**. If you had it on, the popover opens on All after the update.
- The menu bar keeps showing the provider you last picked; All doesn't change it.
