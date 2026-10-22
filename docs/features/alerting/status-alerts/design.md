---
description: Contributor design for StatusAlerts — the one owner of "a login's status got worse under the policy", moved out of QuotaMonitor into Alerting beside QuotaAlerts, telling every alert destination.
---

# Status alerts — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to the
> notification the person has always had at *low*, *critical* and *empty*.
> It answers the Monitoring and Alerting rows of
> [CANONICAL §8](../../../architecture/CANONICAL_MODEL.md#8--where-the-code-is-still-behind):
> the Monitor sends status alerts itself, and names a login by a `"codex."`
> prefix. [Webhooks](../webhooks/design.md) is the first destination besides
> this Mac to hear them.
>
> **Status: DESIGN — not built yet.** User guide: [README.md](README.md).

## The person and the moment

Mia is deep in a run when *Claude · work* turns critical. She wants one
notification saying so — not one per refresh, not one for a login she paused,
and named the way the menu names it. With [webhooks](../webhooks/README.md),
her team's channel wants the same moment.

## Who answers it today, and where it moves

```
 NOW                                              DESIGN
 QuotaMonitor                                     QuotaMonitor  (refreshes; knows nothing after)
  ├─ previousStatuses[login]                         │ onRefreshed(login)
  └─ alerter.alert(id, previous, current)            ├─► QuotaAlerts  ─► .quota(QuotaAlert)
       NotificationAlerter                           └─► StatusAlerts ─► .status(StatusAlert)
        ├─ "only when worse"  ◀── a rule in a           │
        │   notification adapter                        └─► every AlertDestination
        └─ names the login by "codex." prefix,               (Notifications · Webhooks)
            saved accounts, ProviderFactory
```

The Monitor stops being a destination's caller: it drops `previousStatuses`
and `alerter`, and `QuotaAlerter` is removed. "Only when worse" moves from the
notification adapter to the one decider.

## The words

| The screen prints | Means |
|---|---|
| *Claude · work Quota Alert* | the notification's title, the login as the lineup names it |
| *running low* · *critically low* · *depleted* | the status it reached: warning, critical, depleted |

## The laws, one owner each

| Law | Owner |
|---|---|
| a login's status is read under the person's `StatusPolicy`, hidden quotas left out | `QuotaMonitor.status(of:)` (unchanged) |
| tell when a login's status got **worse** and is not healthy; quiet when it stays, improves or recovers | `StatusAlerts` |
| the first status seen for a login is compared with *healthy*, so a login that starts critical is told once | `StatusAlerts` |
| per login, never per product: two Claude logins are two things, each named by its `lineupName` | `StatusAlerts` (handed the name, never looking it up) |
| a paused login is never refreshed, so it is never told | `Account.isPaused` (unchanged) |
| the memory is in memory: after a relaunch a login still critical is told once more | `StatusAlerts` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `StatusAlert` ◇ | `Domain/Alerting/StatusAlerts` | `login` (lineupName), `providerId`, `was`, `now` | **new** |
| `StatusAlerts` ◆ | `Domain/Alerting/StatusAlerts` | `review(_ id:, named:, provider:, status:) async` — keeps each login's last status, decides, tells every destination | **moved** from `QuotaMonitor.handleSnapshotUpdate` and `NotificationAlerter.alert` |
| `Alert` · `AlertDestination` | `Domain/Alerting` | the alert both deciders hand out, and the one port that hears it ([webhooks design](../webhooks/design.md#the-pieces)) | **new** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | words `.status` as today: *Your Claude · work quota is critically low! Save important work.* | **moved** from `NotificationAlerter`, without its naming code |
| `QuotaMonitor` | `Domain/Monitoring` | — | **changed**: drops `previousStatuses`, `alerter` |
| `QuotaAlerter` | `Domain/Monitoring` | — | **removed** |

## The flow

```
onRefreshed(login)
  statusAlerts.review(login.id, named: login.lineupName, provider: login.providerId,
                      status: monitor.status(of: login))      // nil (no usage) → nothing
    was = last[login.id] ?? .healthy;  last[login.id] = now
    if now > was && now != .healthy → for d in destinations: await d.announce(.status(StatusAlert(…)))
```

`QuotaAlerts` runs beside it on the same refresh; the two never read each
other. A quota alert at 35% and a status alert at *low* can both arrive, as
today: they answer different questions.

## Not in it

- A setting to mute status alerts on this Mac. A webhook chooses whether it
  sends them; the Mac's notifications are allowed or not in System Settings.
- The policy's boundaries (20%, 0%) named by the policy rather than repeated in
  `QuotaAlerts` — a separate §8 row.
