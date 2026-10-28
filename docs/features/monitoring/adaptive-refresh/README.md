---
description: Refresh the background quotas faster while one is being used — the wait halves each time a quota rises, down to a minute, and grows back to your interval once it stops. Use when a heavy model burns a quota faster than the menu bar keeps up.
---

# Refresh faster while a quota moves

With Background Sync at 10 minutes, a heavy run can spend a large part of a window before the menu bar shows it. Setting the interval to a minute would keep it fresh, but polls every minute all day, also while nothing is used. **Refresh faster while a quota moves** waits less only while a quota is moving.

## Turn it on

**Settings → Sync & Alerts → *Refresh faster while a quota moves*.** Off by default. It needs a Refresh Interval other than Off.

## What happens

After each background refresh, ClaudeBar compares the quotas with the previous refresh:

- **A quota rose by at least one point:** the next wait is half the last one, never less than a minute.
- **Nothing rose:** the next wait doubles, never more than the interval you chose.

At 10 minutes, a heavy run goes 10 → 5 → 2.5 → 1.25 → 1 minute within about 19 minutes, and back to 10 within about 15 once it stops.

## Gotchas

- **The interval is still the most it waits.** At 1 minute the setting changes nothing.
- **A provider's own floor still wins.** Claude in API mode never refreshes in the background more often than every 15 minutes, moving or not.
- **On battery the wait is still doubled**, and nothing refreshes while the display sleeps.
- **A new window isn't movement.** A quota that resets and starts again doesn't shorten the wait; a rise within the next window does.
- Only what the background refresh covers counts: the menu bar's providers and the selected one. A hidden quota doesn't count.

## See also

- [Menu bar](../../app/menu-bar/README.md), the readout this keeps fresh
- [Settings](../../../settings.md), where the key lives
- [Design](design.md), for contributors
