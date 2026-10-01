---
description: How ClaudeBar colors a quota healthy, warning, critical or depleted, the optional pace-aware burn-rate warning, and custom status colors and High Contrast. Use when a color looks wrong or hard to read.
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

## Pace-aware warnings (burn rate)

A fixed 50% cutoff warns you at 45% left even when the window resets in ten minutes. Burn-rate warnings judge the pace instead.

Turn it on in Settings → **General** → **Burn Rate Warnings**, then pick a **Threshold**: 1.2x, 1.5x (default), 2.0x or 3.0x.

- **Burn rate** = % of the quota used ÷ % of the window elapsed. 1.0 means you'll run out exactly at reset.
- **Warning** when the burn rate is above your threshold **and** under 50% is left. With plenty left, a fast pace isn't worth a warning.
- **Critical and depleted stay absolute.** Under 20% is critical and 0% is depleted, whatever the pace.
- **Healthy** otherwise, even below 50%, if you're on pace.
- Quotas without a known reset time, and the first moment of a window, fall back to the fixed thresholds.

Example: 57% used with 85% of the session gone is a burn rate of 0.67, so it stays healthy. 53% used with 8.5% of the week gone is 6.2, so it's a warning.

Burn rate changes the colors in the menu bar and the popover. **Notifications still use the fixed thresholds.**

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
- The Touch Bar ignores all of this. It colors by percentage with its own fixed blue, amber and red. See [Touch Bar](../touch-bar/README.md).

## See also

[Menu bar](../menu-bar/README.md) · [themes](../themes/README.md) · [settings.md](../../settings.md) for the `app.statusColorOverrides` and `app.highContrastEnabled` keys
