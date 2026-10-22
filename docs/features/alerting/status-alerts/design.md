---
description: Contributor design for StatusAlerts — the one owner of "a login's status got worse under the policy", in Alerting beside QuotaAlerts, following the Monitor's refreshes and telling every alert destination.
---

# Status alerts — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to the
> notification the person has always had at *low*, *critical* and *empty*.
> [Webhooks](../webhooks/design.md) is the destination besides this Mac that
> hears them.
>
> **Status: BUILT.** User guide: [README.md](README.md).

## The person and the moment

Mia is deep in a run when *Claude · work* turns critical. She wants one
notification saying so — not one per refresh, not one for a login she paused,
and named the way the menu names it. With [webhooks](../webhooks/README.md),
her team's channel wants the same moment.

## Who answers it

```
QuotaMonitor  (refreshes; knows nothing after)
  │ onRefreshed(login)
  ├─► QuotaAlerts  ─► .quota(QuotaAlert)
  └─► StatusAlerts ─► .status(StatusAlert)
                         │
                         └─► AlertDestinations: Notifications · Webhooks
```

The Monitor is no destination's caller. "Only when worse" has one owner,
`StatusAlerts`; the notification only words what it is told, and the login
comes named as the lineup names it.

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
| `StatusAlert` ◇ | `Domain/Alerting/StatusAlerts` | `login` (lineupName), `providerId`, `was`, `now` | **built** |
| `StatusAlerts` ◆ | `Domain/Alerting/StatusAlerts` | `review(_:named:provider:status:) async` — keeps each login's last status, decides, tells every destination; `follow(monitor)` hears each refresh | **built** |
| `Alert` · `AlertDestination` | `Domain/Alerting` | the alert both deciders hand out, and the one port that hears it ([webhooks design](../webhooks/design.md#the-pieces)) | **built** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | words `.status`: *Claude · work Quota Alert*, *Your Claude · work quota is critically low! Save important work.* | **built** |
| `QuotaMonitor` | `Domain/Monitoring` | refreshes; `status(of:)` under the policy, hidden quotas left out | **built** |

## The flow

```
onRefreshed(login)                                         // statusAlerts.follow(monitor)
  statusAlerts.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                      status: monitor.status(of: login))      // nil (no usage) → nothing
    was = last[login.id] ?? .healthy;  last[login.id] = now
    if now > was && now != .healthy → await destination.announce(.status(StatusAlert(…)))   // AlertDestinations
```

`QuotaAlerts` runs beside it on the same refresh; the two never read each
other. A quota alert at 35% and a status alert at *low* can both arrive:
they answer different questions.

## Not in it

- A setting to mute status alerts on this Mac. A webhook chooses whether it
  sends them; the Mac's notifications are allowed or not in System Settings.
- The policy's boundaries (20%, 0%) named by the policy rather than repeated in
  `QuotaAlerts` — a separate §8 row.
