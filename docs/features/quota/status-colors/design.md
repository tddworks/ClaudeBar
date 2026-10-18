# Status colors — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to how a status is
> coloured. Users: [README.md](README.md). What a status *is* is a law of the
> model (`StatusPolicy`, [CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> its colour is the page's.

| Law | Owner |
|---|---|
| per status, the first that answers: the person's own colour → the High Contrast palette → the theme's | `StatusColorPolicy` |
| a theme is never edited to apply them: the resolved theme is wrapped when the policy is active, and stored themes stay pure | `ThemeRegistry.resolveTheme(…statusColors:)` · `StatusColorOverridingTheme` |
| every High Contrast colour reads at 4.5:1 or better against a typical light and dark menu bar | a Domain test, over `StatusPalette` |

## Gotchas

- **Read the policy inside the view's own observation scope.**
  `AppThemeProviderModifier` and `NotchRootView` read
  `AppSettings.shared.statusColorPolicy` themselves; a policy handed in from
  outside doesn't redraw when it changes.
- **The wrapper doesn't forward `statusColor(for:)` or
  `progressGradient(for:)`.** The protocol's defaults build them from the four
  overridden colours, which is what makes the override reach bars too — a theme
  that overrides those two methods loses the person's colours.
