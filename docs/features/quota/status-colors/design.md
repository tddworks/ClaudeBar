---
description: Contributor design for a quota's status and its colour: the absolute bands, the pace-aware policy that reads SpendRate's one rule, the surfaces that take the policy, and how a status picks its colour.
---

# Status colors — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to the Quota kernel
> and the App: what a status *is* is a law of the model (`StatusPolicy`,
> [CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> its colour is the page's. Users: [README.md](README.md). The rate it reads:
> [forecast](../../monitoring/forecast/design.md).

> **Status: BUILT.**

## 1 · What a person asks, and what is true

Mia glances at the menu bar between two tasks. Her question is **"do I need to
act?"**: slow down, switch login, or carry on. The colour answers it before she
reads a number, and a notification or webhook answers it when she isn't looking.

What is true: every quota has a `left` and, when the vendor states one, a
`window`. The share left alone gives a fixed answer: under 50% is worth a look,
under 20% is urgent, 0 is gone. The person can also ask for a smarter answer:
*warn me when, at this pace, it runs out before it refills*. That is the
question the Pace badge (*Running hot*) and the forecast (*Runs out in…*)
already answer, from one rule. The status asks the same rule, so one card never
says *On track* beside a low status.

## 2 · The words

| Word | Means |
|---|---|
| **status** | healthy · warning · critical · depleted: the answer to "do I need to act?" |
| **absolute** | the policy that reads only the share left: depleted at 0, critical under 20, warning under 50 |
| **pace-aware** | the policy that, from 20% left up, warns exactly when the quota runs out before it resets |
| **rate** | `SpendRate`: the share used over the share of the window gone |
| **runs out before reset** | used more than 5 points (`SpendRate.margin`) ahead of the share of the window gone |
| **noise floor** | 3% of the window gone: before it there is no rate, and pace-aware falls back to absolute |

## 3 · The model

```text
StatusPolicy  ◇  .absolute | .paceAware          the person's one judgement, for the whole app
  └ UsageQuota.status(under: policy)  → QuotaStatus
      ├ .absolute   → quota.status                    QuotaStatus.from(percentRemaining:)
      └ .paceAware  → no rate yet       → quota.status (absolute)
                      left < 20 or 0    → critical / depleted (absolute)
                      else quota.rate: SpendRate
                             └ runsOutBeforeReset ? warning : healthy
UsageSnapshot.overallStatus(under: policy)  → the worst quota's status
```

The pace-aware branch reads `percentLeft`, the same share left the rate reads,
so a capped money quota is judged by its money on both sides.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| depleted at 0, critical under 20, warning under 50, otherwise healthy; a balance with no ceiling is healthy until it is spent | `QuotaStatus.from(percentRemaining:)` · `StatusPolicy.absolute` |
| a quota is spent too fast ⇔ it runs out before its reset: used more than 5 points ahead of the share of the window gone | `SpendRate.runsOutBeforeReset` |
| under pace-aware, depleted and critical stay absolute; from 20% up a quota warns exactly when it runs out before its reset; with no rate it falls back to absolute | `StatusPolicy` (`UsageQuota.status(under:)`) |
| a snapshot's status is its worst quota's | `UsageSnapshot.overallStatus(under:)` |
| every surface reads the status under the monitor's one policy, never a copy of the rule | `QuotaMonitor.statusPolicy` |
| tell once when a login's status gets worse; nothing on recovery | `StatusAlerts` |
| per status, the first colour that answers: the person's own → High Contrast → the theme's | `StatusColorPolicy` |
| a theme is never edited to apply them: the resolved theme is wrapped when the policy is active, and stored themes stay pure | `ThemeRegistry.resolveTheme(…statusColors:)` · `StatusColorOverridingTheme` |
| every High Contrast colour reads at 4.5:1 or better against a typical light and dark menu bar | a Domain test, over `StatusPalette` |

## 5 · One rule, every reader

```text
                         SpendRate.runsOutBeforeReset
                         (used − gone > 5, the only "too fast")
                ┌──────────────────┼──────────────────────┐
           UsagePace          Forecast              StatusPolicy.paceAware
         "Running hot"     "Runs out in…"         warning (from 20% left up)
                                                         │
                         QuotaMonitor.statusPolicy  ◄────┘   { AppSettings.shared.statusPolicy }
                                   │
   ┌──────────────┬────────────────┼────────────────┬───────────────────┬──────────────────┐
menu-bar label   cards, bars,   StatusAlerts →    Touch Bar          status export      Notify! gauge
(monitor's       pills          notifications,    (status(under:))   (the label's        (statusPolicy:)
 menuBarLabel →  (status(under:  webhooks          status)
 Display(policy:)) settings.      (monitor.status
                  statusPolicy))  (of:))
```

`MenuBarPercentageDisplay(quota:mode:policy:)` and
`MenuBarDurationDisplay(quota:policy:)` take the policy; the monitor's
`menuBarLabel`, `additionalMenuBarLabels` and the two display helpers pass its
own `statusPolicy`, so the drivers pass nothing. The notch still reads the
absolute bands ([CANONICAL §8](../../../architecture/CANONICAL_MODEL.md#8--where-the-code-is-still-behind)).

## 6 · The pieces

| File | Role |
|---|---|
| `Modules/Quotas/Sources/QuotaStatus.swift` | the four statuses, the absolute bands, severity order |
| `Modules/Quotas/Sources/SpendRate.swift` | the rate, the noise floor, the margin, `runsOutBeforeReset` |
| `Modules/Quotas/Sources/StatusPolicy.swift` | the two policies; `status(under:)` and `overallStatus(under:)` |
| `Modules/Monitoring/Sources/QuotaMonitor.swift` · `Sources/Domain/App/QuotaMonitor+MenuBar.swift` | holds the policy; the menu-bar label and a login's status read it |
| `Sources/Domain/App/MenuBar{Percentage,Duration}Display.swift` | a menu-bar readout's status under the policy |
| `Sources/Domain/Alerting/StatusAlerts/StatusAlerts.swift` | tells once when a login's status gets worse |
| `Sources/App/Settings/AppSettings.swift` | `burnRateWarningEnabled` → `statusPolicy` |
| `Sources/App/Views/SettingsWindow/GeneralPane.swift` | the switch and its words |
| `Sources/Domain/App/StatusColorPolicy.swift` · `Sources/App/Theme/StatusColorOverridingTheme.swift` | a status's colour |

## 7 · What the person sees

| Left · window gone | Pace | Absolute | Pace-aware |
|---|---|---|---|
| 58% · 41% | On track | healthy | healthy |
| 60% · 15% (45% used) | Running hot | healthy | **warning** |
| 40% · 90% | Room to spare | warning | **healthy** |
| 25% · 60% | Running hot | warning | warning |
| 15% · any | any | critical | critical |
| 0% · any | — | depleted | depleted |
| 40% · 2% (under the floor) | unknown | warning | warning |
| 35% · no window | unknown | warning | warning |

## 8 · Settings

| Key | Meaning |
|---|---|
| `app.burnRateWarningEnabled` | `true` → `StatusPolicy.paceAware`; `false` or absent → `.absolute`. The key keeps its name so a saved choice is kept |
| `app.burnRateThreshold` | retired: never read or written; a saved value is ignored |

The switch reads **Warn when a quota will run out before it resets**; its words
are the App's.

## 9 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| a new policy (say, warn on *On track* too) | a new `StatusPolicy` case and its branch in `status(under:)` |
| a new surface coloured by status | it takes `policy: StatusPolicy`, or reads `monitor.statusPolicy`, and calls `status(under:)` |
| a different "too fast" (another margin, a weighted rate) | `SpendRate`: Pace, the forecast and the status follow together |
| different colours | the theme, or `StatusColorPolicy` |

## 10 · Gotchas

- **Read the colour policy inside the view's own observation scope.**
  `AppThemeProviderModifier` and `NotchRootView` read
  `AppSettings.shared.statusColorPolicy` themselves; a policy handed in from
  outside doesn't redraw when it changes.
- **The wrapper doesn't forward `statusColor(for:)` or
  `progressGradient(for:)`.** The protocol's defaults build them from the four
  overridden colours, which is what makes the override reach bars too; a theme
  that overrides those two methods loses the person's colours.
- **A status is read as of now.** `status(under:)` reads the rate at the
  current moment; tests pass `at:` to fix the clock.
