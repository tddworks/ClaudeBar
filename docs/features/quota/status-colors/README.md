---
description: How ClaudeBar colors a quota healthy, warning, critical or depleted, the optional warning when a quota will run out before it resets, and custom status colors and High Contrast. Use when a color looks wrong or hard to read.
---

# Status Colors

Every quota window has a status, and the status picks its color in the menu bar, the popover, the notch and Settings. A provider's overall status is its worst window.

## Thresholds

| Status | Remaining | Notification |
|---|---|---|
| Healthy | 50% or more | none |
| Warning | 20% to under 50% | "quota is running low" |
| Critical | above 0%, under 20% | "quota is critically low" |
| Depleted | 0% | "quota is depleted" |

The cutoffs are fixed; there is no setting for them. Settings → Appearance → Status Colors shows them under each level.

**Notifications** fire when a provider's overall status gets worse, for example healthy → warning, or warning → critical. Nothing fires when it recovers. macOS asks for notification permission the first time.

## Warn when a quota will run out before it resets

A fixed 50% cutoff warns you at 45% left even when the window resets in ten minutes, and says nothing at 60% left when you are burning through it in the first hour. This switch judges the pace instead.

Turn it on in Settings → **General** → **Warn when a quota will run out before it resets**. There is nothing else to set.

With it on, a quota's status follows the same answer as its **Pace** badge and its forecast line:

- **Warning** when, at its pace, the quota runs out before it refills: the badge says *Running hot* and the forecast says *Runs out in…*. This holds at any level from 20% left up, so 60% left can be a warning.
- **Healthy** when it lasts until it resets: the badge says *On track* or *Room to spare*. This holds even below 50% left.
- **Critical and depleted stay absolute.** Under 20% is critical and 0% is depleted, whatever the pace.
- **The fixed thresholds apply until there's a pace**: in a window's first minutes (under 3% of it gone), for a quota with no reset time or window length, and for a balance with no ceiling.

"Runs out before it refills" means more than 5 points more of the quota used than of the window gone. Within 5 points either way you're on the line, and it reads *On track* and healthy.

Examples, in a 5-hour session:

| Left | Window gone | Pace | Status (off) | Status (on) |
|---|---|---|---|---|
| 58% | 41% | On track | Healthy | Healthy |
| 60% | 15% | Running hot | Healthy | **Warning** |
| 40% | 90% | Room to spare | Warning | **Healthy** |
| 15% | 95% | Room to spare | Critical | Critical |

A card never shows a low status beside *On track*.

**What follows it:** the status, and so its colour, in the menu bar, the provider pills, the cards and bars in the popover, the Touch Bar and the status export. The **"running low"** notifications and webhooks follow it too: they fire when a login's status gets worse under this same setting. Your own [quota alerts](../../alerting/quota-alerts/README.md) are separate: they fire at the percentages you set. The notch still colours by the fixed thresholds.

## Custom colors and High Contrast

Settings → **Appearance** → **Status Colors**:

- **High Contrast**: a built-in palette where every level clears a 4.5:1 contrast ratio against both light and dark menu bars. It follows the menu bar's own appearance, which on recent macOS depends on the wallpaper behind it, not only on Light/Dark mode.
- **Healthy / Warning / Critical / Depleted**: a color well for each. Pick a color and the row shows **Custom** with a clear button (×) that goes back to the default for that level.
- **Reset to defaults** clears all four custom colors.

Which color wins, per level:

1. Your custom color for that level
2. The High Contrast palette, if it's on
3. The theme's own color

So you can turn on High Contrast and still override just one level. Custom colors apply to every theme, including imported ones.

## Gotchas

- The stock theme colors are tuned for the dark popover. On a light menu bar the greens and ambers can be hard to read, and High Contrast fixes that.
- The depleted color is a darker red or pink, depending on the theme. It isn't gray.
- The Touch Bar follows the status, but draws it in its own fixed blue, amber and red, not your custom colors. See [Touch Bar](../../alerting/touch-bar/README.md).

## See also

[design.md](design.md) · [Menu bar](../../app/menu-bar/README.md) · [themes](../../app/themes/README.md) · [Forecast](../../monitoring/forecast/README.md) · [settings.md](../../../settings.md) for the `app.burnRateWarningEnabled`, `app.statusColorOverrides` and `app.highContrastEnabled` keys
