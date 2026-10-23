---
description: Contributor design for RecapAlerts — the one owner of "the week turned and its recap hasn't gone out", following the Monitor's refreshes and telling the recap destinations (today the webhooks that send recaps).
---

# Recap alerts — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to journey moment
> 19a's other half: the team should also hear **what the week added up to**,
> where they already look. It composes two built features: the
> [recap](../../usage-history/recap/design.md) — whose design deferred exactly
> this as *the Monday notification* — and the
> [webhooks](../webhooks/design.md), which gain the recap as their third kind
> of send.
>
> **Status: BUILT** (webhook destinations). User guide: [README.md](README.md).
> The Mac's own Monday notification stays deferred — see *Not in it*.

## The person and the moment

Mia reads the **Weekly recap** card every week, and her team's Slack channel
already hears the quota alerts. On Monday morning she pastes the week's
numbers into the channel by hand — the same numbers her Mac has already added
up. She wants the recap the card reads to arrive in the channel when the week
turns, without her, in the same message a webhook already speaks.

She does not want a second scheduler, a server, or a recap for a week nobody
worked.

## Who already answers it

| The part | Already owned by |
|---|---|
| what the week added up to, in one unit, against the week before | `Recap` ([design](../../usage-history/recap/design.md)) |
| reading both weeks across the lineup | `WeeklyRecaps` |
| where a week starts | the person's calendar, through `DateRange.week` |
| who hears what was decided | `Webhooks`, a destination ([design](../webhooks/design.md)) |
| the moment a decision is told | the decider following `QuotaMonitor.onRefreshed`, as `QuotaAlerts` and `StatusAlerts` do |

So a recap alert is **a decision the app already has the parts for**: the week
turned, and the week that closed hasn't gone out. The recap is never an edit
to the Monitor and never a timer of its own — it asks at every refresh, and
the answer is pure.

## The words

| The screen prints | Means |
|---|---|
| *Weekly recap* | the third tick in a webhook's **SENDS** list, beside *Quota alerts* and *Status alerts* |
| *When your week turns: the week that closed, across every provider* | the tick's hint — the week is the calendar's, so its first day is wherever the person's week starts |
| in Slack: *Weekly recap Nov 3–9: $12.34, +20% vs the week before. …* | the recap's one message, built by `WebhookBody` |
| *Sent 2m ago* · *Failed — 404* | the webhook's last delivery, as for any send |

## The tree

```
QuotaMonitor.onRefreshed(login) ─► RecapAlerts.review()                 (follow, as StatusAlerts does)
    │
    ├─ RecapDue.week(containing: now, lastSentAt:, calendar:) → DateRange?     ◇ pure — no timer
    │     nil while the week of the last send is still the week holding now;
    │     otherwise the week that closed (the one before now's)
    │
    ├─ WeeklyRecaps.readIfStale()          the one read — the card's own
    ├─ WeeklyRecaps.recap(of: due.week)    nil while its read covers other weeks
    ├─ memory.setLastSent(now)             the week has had its moment
    └─ !recap.isEmpty → RecapDestination.announce(RecapAlert) ◇
          recap · week · calendar · names
          │
          └─► Webhooks (a RecapDestination) → every webhook with *Weekly recap* ticked

Saved: settings.json  alerts.recapSentAt        ← RecapSentRepository (JSONSettingsRepository)
```

## The laws, one owner each

| Law | Owner |
|---|---|
| a week's recap is due from the first moment of the calendar week that isn't the week the last send was for — the calendar's own first weekday, never a fixed Monday; the recap due is of the week that closed | `RecapDue` |
| the due answer is pure: `now`, the last send and the calendar decide, nothing is remembered and no timer runs; the decider asks at every refresh | `RecapDue` · `RecapAlerts` |
| the recap sent is read by `WeeklyRecaps`, the card's own read — never a second read of the logs; a read that didn't finish this week's read sends nothing and waits for the next refresh | `RecapAlerts` (through `WeeklyRecaps.readIfStale`, `recap(of:)`) |
| a week is sent for once: its moment is marked when the recap has been read, whether or not a webhook wanted it or a POST arrived — the next week is the next recap, and a relaunch inside the week sends again never. The mark is the week's, not a webhook's: a webhook that starts sending recaps mid-week hears the next week that closes; only never sent (a fresh install) is due at once | `RecapAlerts` · `RecapSentRepository` |
| a week that added up to nothing says nothing — silence, not a message of zeros; the Mac that slept all week stays quiet | `RecapAlerts` |
| no backlog: after an absence the return sends the week that closed last — one recap — never the weeks missed | `RecapDue` |
| a week that closed while the Mac was off goes out at the first refresh after launch — the days are kept in the ledger, so the closed week still reads whole | `RecapAlerts` |
| the recap rides the refreshes, as every alert does; with background refresh off it waits for the first interactive one | `RecapAlerts.follow(_:)` |
| a webhook wants the recap when it is on and sends recaps; scope is never judged — the recap is one read across every provider, so no login and no provider is in or out of it | `Webhook.wants` ([webhooks design](../webhooks/design.md)) |
| the recap is not an `Alert`: an alert names a login and its provider, and the recap names the week. It goes to its own destination port, as In use's worth-switching notice does | `RecapAlert` · `RecapDestination` |
| what the recap reads in, what it sums and when it has no change are `Recap`'s laws, unchanged | `Recap` |
| the recap send never reads the popover's *Weekly recap* section switch — that shapes the popover; the webhook's tick is the whole choice | `Webhook.Sends` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `RecapDue` ◇ | `Domain/Alerting/RecapAlerts` | `week(containing:lastSentAt:calendar:) → RecapDue?` — the once-per-calendar-week answer, pure | **built** |
| `RecapAlert` ◇ | `Domain/Alerting/RecapAlerts` | the week that closed, told: the `Recap`, its week, the calendar the week was read in, the providers named as the lineup names them | **built** |
| `RecapDestination` (port, `@Mockable`) | `Domain/Alerting/RecapAlerts` | `announce(_ recap: RecapAlert) async` — who hears the week's recap | **built** |
| `RecapAlerts` ◆ | `Domain/Alerting/RecapAlerts` | `review() async`, `follow(_ monitor:)` — asks `RecapDue` at every refresh, reads through `WeeklyRecaps`, marks the week sent, tells the destination | **built** |
| `RecapSentRepository` (port, `@Mockable`) · `JSONSettingsRepository` | `Domain/Alerting/RecapAlerts` · `Infrastructure/Settings` | when the last recap went out — `alerts.recapSentAt` in `settings.json`, so a relaunch inside the week sends again never | **built** |
| `WeeklyRecaps.recap(of:)` | `Domain/UsageHistory` | the recap of a week that closed before the read, or nil while the read covers other weeks — `WeeklyRecaps` says whether its read is fresh, the sender never judges it | **built** |
| `Webhook.Sends.recap` · `WebhookBody.Message.recap` | `Domain/Alerting/Webhooks` | the third kind of send: a field in the webhook and a case in the body, and nothing else moves ([webhooks design](../webhooks/design.md)) | **built** |
| `Webhooks` | `Domain/Alerting/Webhooks` | an `AlertDestination` and now a `RecapDestination`: delivers the recap body to the webhooks that want it | **built** |
| `QuotaMonitor` | `Domain/Monitoring` | refreshes; every decider follows through `onRefreshed` | built |

## The flow

```
recapAlerts.follow(monitor)                                          (composition root)

onRefreshed(login) → RecapAlerts.review()
  guard let due = RecapDue.week(containing: now(), lastSentAt: memory.lastSent(), calendar:)  // nil → nothing
  await recaps.readIfStale()                                   // the card's read; cheap when it is fresh
  guard let recap = recaps.recap(of: due.week) else { return }  // nil while the read left standing covers other weeks
  memory.setLastSent(now())                                    // the week has had its moment
  guard !recap.isEmpty else { return }                         // nothing added up: silence
  await destination.announce(RecapAlert(recap:, week: due.week, calendar:, names:))
```

`Webhooks.announce(recap)` delivers to `list.filter { $0.wants(recap) }` —
on, and *Weekly recap* ticked, scope unjudged — and records each delivery as
any send. *Send a test* still sends the test message, never a made-up recap.

## What is sent

JSON, every key on every send (`null` where there is no value); Slack one
message in the body's own words:

```json
{ "type": "recap", "unit": "cost", "total": 12.34, "change": 0.2,
  "weekStart": "2026-11-02T00:00:00Z", "weekEnd": "2026-11-08T00:00:00Z",
  "providers": [ { "provider": "claude", "name": "Claude", "value": 7.65, "share": 0.62 } ],
  "topModel": "claude-sonnet-4-5", "biggestDay": "2026-11-05",
  "cacheSavings": 1.02, "workingTime": 40800, "sessions": 34,
  "tokens": null, "sentAt": "2026-11-09T00:05:00Z" }
```

```
Weekly recap Nov 3–9: $12.34, +20% vs the week before. Claude 62% · Codex 38%.
Top model claude-sonnet-4-5 · biggest day Nov 5 · cache saved $1.02.
```

Clauses the week doesn't have are left out of the Slack message; `change` and
`tokens` are `null` in JSON when there is no change or the total already reads
in tokens. Money reads through the kernel's `MoneyFormat`; counts, shares and
changes through its `UsageNumberFormat`, the chart's own (K · M · B). The dates are written Gregorian in the week's zone —
the person's calendar holds the week's boundaries, the numbers on the page stay
Gregorian whatever calendar they keep — so a body never guesses a zone. What
leaves the Mac: the totals, the
provider names as the lineup says them, the top model's name and the days —
no path, no prompt, no session.

## Saved

```json
"alerts": {
  "recapSentAt": 1793670500,
  "webhooks": [
    { "id": "9F2C…", "channel": "slack", "quotaAlerts": true, "statusAlerts": false,
      "recap": true, "isOn": true, … }
  ]
}
```

`recap` reads back `false` for a row saved before the field — a webhook never
sent recaps unasked. `recapSentAt` is a timestamp; the week it falls in is
`RecapDue`'s reading of it, never kept.

## Considered and rejected

| Considered | Rejected because |
|---|---|
| the recap as a third `Alert` case, riding `AlertDestinations` | an alert names a login (`lineupName`) and its provider, and a webhook's scope judges it; the recap names neither, so `Alert` would bend — `login` optional, scope meaningless — and every consumer moves. In use's worth-switching notice is the precedent: a second value and a second port |
| a Monday timer or a background daemon | the refreshes are the cadence every decider rides; the due answer is pure, so no timer is needed and none is tested |
| keeping the last send in memory, like `StatusAlerts` | a relaunch inside the week would send the recap again, every launch — a weekly report must be sent once a week, so its memory outlives a relaunch |
| sending the empty week, as the card says *Nothing this week* | the card speaks because the person is looking; a push that says "$0.00" is noise, and the Mac that slept all week would spam zeros on return. Silence is the honest empty |
| a backlog of missed weeks after an absence | the recap answers *what did last week add up to* — a cadence, not a queue; webhooks already refuse queues ("one POST, no retry"), and a return from three weeks away would flood the channel |
| sending only what the popover's *Weekly recap* section shows | that switch shapes the popover, not the webhook; the webhook's tick is the whole choice |
| the decider reading the logs itself | `WeeklyRecaps` is the one read; a second read of the same logs is a second truth, and the card and the sender could disagree |

## Not in it

- **The Mac's Monday notification** — still deferred, exactly as the recap's
  design left it: it would be a second `RecapDestination`, and nothing here
  moves when it comes.
- A monthly recap, a per-webhook day or hour, a per-provider recap — each is a
  change to `RecapDue` or to what the sender reads, not a new fan-out.
- Retries or a send that waits across a relaunch — the webhooks' own law.
- The shareable image — still the Leaderboard's *exactly what gets shared*
  step.
