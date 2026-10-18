# Quota alerts — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to journey moment 19:
> a notification at the percentage the person cares about, sooner than the
> built-in 20%. The laws are the model's
> ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says which piece keeps them. Issue [#68](https://github.com/tddworks/ClaudeBar/issues/68),
> first built in [#447](https://github.com/tddworks/ClaudeBar/pull/447).
>
> **Status: BUILT.** Mockup: [design-concept/quota-alerts](../../../../design-concept/quota-alerts/index.html).

## The question, and who already answers part of it

*Tell me when I'm below 35%.* The status alerts already say *below 20%* and
*empty*, and turn the menu bar amber or red; they stay as they are. A quota
alert is the person's own percentage, beside them — not a new status, not a
colour.

It follows a refresh, so it is not the Monitor's: it observes through
`onRefreshed`, the way In use does, and the Monitor and `QuotaAlerter` don't
change.

## The pieces

| Piece | One job | Changes when |
|---|---|---|
| `QuotaAlerts` (`Domain`) ◆ | the person's percentages (`add`, `remove`, `percents`), and `review(login, usage:, name:)` after each refresh: which percentages the login just fell below | the rule for when to say it changes |
| `QuotaAlertSettingsRepository` (port, `Domain`) · `JSONSettingsRepository` | the percentages, kept as `alerts.thresholds`: `[35, 60]` | where they are kept changes |
| `QuotaAlertAnnouncer` (port, `Domain`) · `QuotaAlertNotifications` (`Infrastructure`) | tell the person, through the macOS notifications ClaudeBar already sends | the wording or the channel changes |
| the composition root | `monitor.onRefreshed { login in quotaAlerts.review(login, usage: monitor.usage(of: login), name: …) }` | never for quota alerts |

`monitor.usage(of:)` is the usage with the person's hidden quotas already left
out, so `QuotaAlerts` never sees a quota nobody watches.

## The rules

| Rule | Why |
|---|---|
| once below, quiet while below, again only after climbing to the percentage + 1 | a quota hovering at 35.0 / 34.9 would otherwise notify on every refresh |
| the lowest share left among the login's quotas; a money quota with a ceiling is a share (`$10 of $50` = 20%), a balance without one is skipped | `Quota.left`: a balance has no percentage to fall below |
| per login, by the name the lineup prints | two Claude logins are two things Mia watches (F11) |
| whole percents, 1–99, at most five; 20 and 0 are refused with *Already alerted* | 20% and 0% are the status alerts; a second notification for the same moment is noise |
| the state lives in memory | after a relaunch a login still below a percentage is told once more, which is the honest answer to *am I below?* |

## Not in it

- Per-provider percentages, Notify! as a channel — added when someone asks, problem first.
- Any change to the menu bar colour or the status alerts.
