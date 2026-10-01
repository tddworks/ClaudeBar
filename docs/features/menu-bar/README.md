---
description: Show quota percentage and reset countdown for up to three providers right in the menu bar, one or two windows each, single-line or stacked. Use when choosing what the menu bar label shows.
---

# Menu Bar

The menu bar item can show a live readout for up to three providers, so you can check a quota without opening the popover. With the readout off, it shows a status icon tinted by the selected provider's overall status.

## Quick start

1. Settings → **Menu Bar**.
2. Turn on **Show Percentage in Menu Bar**, **Show Duration in Menu Bar**, or both.
3. Under **Providers**, pick up to three (`n / 3 selected`). Each one then gets its own card below.
4. In each provider's card, pick the **Quota** to show and, if you like, a **Secondary Quota**.

The Providers card only appears once percentage or duration is on. Only providers enabled under Settings → Providers are offered.

## What the label shows

| Setting | Label |
|---|---|
| Both off | Status icon only (bar chart, triangle when critical), no numbers |
| Percentage | `62%` |
| Duration | `4:40` |
| Both | `62% · 4:40` |
| With a secondary quota | `5h 62% · 4:40 \| 7d 34% · 2d` |

- **Quota Display** (top of the pane) picks what the percentage means: remaining or used. The third, gauge-icon choice is Pace: popover cards show "Running hot" / "On track" / "Room to spare", and the menu bar shows the remaining percentage.
- With two windows, each one is labelled by the probe's short menu bar title or the window type (`5h`, `7d`, a model name). The label takes the worse of the two statuses, and **Stack in Menu Bar** draws them as two smaller lines with their own colors. Stacked text comes in Small, Medium or Large.
- With more than one provider, each readout starts with that provider's logo, separated by `|`. Hover the item to see a tooltip with the provider names.
- The color of each readout follows its quota status; see [status colors](../status-colors/README.md).

## Countdown format

The duration is the time until the quota window resets:

| Time left | Shown as |
|---|---|
| A day or more | `2d` |
| 1 to 24 hours | `4:40` (hours:minutes) |
| 1 to 59 minutes | `45m` |
| Under a minute | `soon` |
| Unknown | `—` |

The countdown updates on its own every half second while a duration is shown, and in the `H:MM` range the colon pulses so you can see it's live. The design is in [countdown-colon.md](countdown-colon.md).

## Several providers

- The first provider you select is the primary one. You can't deselect the last one, and a fourth can't be added until you remove one.
- Each provider keeps its own quota, secondary quota and stacking choice. Removing a provider from the menu bar doesn't clear them; select it again and they come back.
- A selected provider that you turn off under Settings → Providers stays selected but drops out of the label. Its card says "Enable this provider in Providers to show its usage."
- A provider that's selected but has no data yet shows `—`. Its card says "Waiting for quota data… Your choices are saved."
- If the saved quota disappears from a provider (a plan change, a renamed window), the card says "The saved quota is unavailable. Choose another quota below."

## Gotchas

- **Background refresh is off by default.** With Settings → **Sync & Alerts** → Refresh Interval set to Off, the numbers update only when you open the popover. Choose 1, 5, 10 or 15 minutes to keep the menu bar current. Background refresh covers only the menu bar providers and the selected one.
- The countdown ticks between refreshes, but the percentage only changes when a refresh arrives.
- With **Burn Rate Warnings** on (Settings → General), the colors follow your consumption pace, not the fixed thresholds.
- While a Claude Code session is working, a terminal glyph appears in front of the readout. It needs [session hooks](../session-hooks/README.md).

## See also

[countdown-colon.md](countdown-colon.md) · [status colors](../status-colors/README.md) · [themes](../themes/README.md) · [Touch Bar](../touch-bar/README.md) · [notch](../notch/README.md)
