---
description: Get a notification when a login's quota falls below a percentage you pick, sooner than the built-in 20%. Use when setting up quota alerts or when one doesn't arrive.
---

# Quota alerts

ClaudeBar already alerts you when a quota drops below 20% and when it's empty, and colours the menu bar. Quota alerts add your own percentages, so you hear at the point you care about: 35% before a long run, 60% when a job mustn't stop.

## Set up

**Settings → Sync & Alerts → Quota Alerts**:

1. Type a whole percent from 1 to 99 (`35`, or `35%`) and press **Add** or Return.
2. Keep up to five. Remove one with the **×** on its chip.

20% and empty can't be added: ClaudeBar already alerts there, and you'd get two notifications for the same moment.

## When it tells you

- After a refresh, when a login's lowest quota is below one of your percentages: *Claude · work is below 35%*, *34% left.*
- **Once.** It stays quiet while the quota stays below, and tells you again only after the quota climbs back at least a point above your percentage.
- **Per login.** With two Claude accounts, each is told on its own, by the name the menu bar shows.
- Quotas you hid in the popover are left out. A prepaid balance with no limit has no percentage, so it never triggers an alert.

## Gotchas

- **Nothing arrives**: allow ClaudeBar in **System Settings → Notifications**. With **Background Sync** off, the check runs only when you refresh or open the menu.
- **Told again after a restart**: ClaudeBar remembers what it told you only while it runs, so a login still below your percentage is told once more after a relaunch.
- Alerts are the same for every provider, and go to macOS notifications only, not to [Notify!](../notify/README.md).

## See also

[design.md](design.md) · [status colors](../../quota/status-colors/README.md) · [settings.md](../../../settings.md) for `alerts.thresholds`
