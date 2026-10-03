---
description: Get a notification when a provider's remaining quota falls below a percentage you pick. Use when setting up quota alerts or when a threshold does not fire.
---

# Quota alerts

ClaudeBar always colors the menu bar and sends the built-in status alerts at 50%, 20% and 0%. Quota alerts let you add your own percentages, so the notification arrives at the point where *you* start to care — 35% before a long run, 75% when a job must not be interrupted.

## Set up

Everything is in **Settings → Sync & Alerts → Below-Threshold Alerts**.

1. Type a percentage (for example `35`) and press **Add**, or hit Return.
2. Add as many as you like, up to eight.
3. Remove one with the **−** button next to it.

The list is stored in `~/.claudebar/settings.json` and survives restarts.

## How it fires

- The check runs after every refresh of a provider and looks at that provider's **lowest quota window** — if any window is below a threshold, the provider has crossed.
- Each threshold fires **once per crossing**. While the percentage stays below, it stays quiet.
- It fires again only after the quota **recovers** past the threshold (by about one percentage point, so hovering exactly at the boundary cannot spam you).
- Notifications arrive through the same macOS notifications ClaudeBar already uses. The permission is requested the first time you open the menu; if you denied it there, allow ClaudeBar in **System Settings → Notifications**.

If nothing fires: the alert is sent on the refresh *after* the percentage drops below the threshold, so with background sync off you'll see it when you next open the menu or refresh.

## What is not included

- Thresholds are global, not per provider.
- They reuse the existing notification channel; they are not sent to Notify!.
- The fixed 50/20/0 status alerts and the menu bar colors are unchanged.
