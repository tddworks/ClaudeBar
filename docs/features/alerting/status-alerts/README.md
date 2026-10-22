---
description: The notification ClaudeBar sends when a login's quota gets worse — running low, critically low, depleted — and how a webhook can send it too. Use when a status notification arrives twice, never, or under the wrong name.
---

# Status alerts

ClaudeBar tells you, once, when a login's quota gets worse: *running low* (below 50%), *critically low* (below 20%), *depleted* (empty). With *Warn when a quota will run out before it resets* on, *running low* means it runs out before it refills, at any level from 20% up ([status colors](../../quota/status-colors/README.md)). These are the alerts the menu bar's colours come from; your own percentages are [quota alerts](../quota-alerts/README.md).

## When it tells you

- When a login's status **gets worse**: healthy → low, low → critical, critical → depleted. Not while it stays there, and not when it recovers.
- **Per login**, named as the menu names it: *Claude · work Quota Alert*.
- Quotas you hid in the popover are left out.
- A **paused** login is never refreshed, so it is never told.

## Somewhere else

A [webhook](../webhooks/README.md) with **Status alerts** ticked sends the same moment to Slack or your own URL.

## Gotchas

- **Nothing arrives**: allow ClaudeBar in **System Settings → Notifications**.
- **Told again after a restart**: a login that is still critical is told once more after a relaunch.

## See also

[design.md](design.md) · [Quota alerts](../quota-alerts/README.md) · [Webhooks](../webhooks/README.md)
