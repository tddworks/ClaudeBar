---
description: Contributor design for Webhooks — a destination that POSTs the alerts ClaudeBar already decides (quota alerts, status alerts) to Slack or a URL the person owns. Covers the words, the laws and their owners, the pieces, the flows and privacy.
---

# Webhooks — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to journey moment
> 19a ([USER_JOURNEYS](../../../architecture/USER_JOURNEYS.md)): *tell my team,
> where they already look*. The laws are the model's
> ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says which piece keeps them. Its sibling is [status alerts](../status-alerts/design.md),
> which gives webhooks their second kind of alert.
>
> **Status: DESIGN — not built yet.** Mockup: [design-concept/webhooks](../../../../design-concept/webhooks/index.html).
> User guide: [README.md](README.md).

## The person and the moment

**Mia** runs Claude Code for a small team. She already gets a notification
when *Claude · work* falls below 35% ([quota alerts](../quota-alerts/README.md)),
but the team doesn't: they find out when a run stops. She wants the same
alert in the team's Slack channel, and Lin wants it as JSON on a script that
pauses the overnight jobs.

Neither wants a second set of percentages. *Below 35%* is already the
person's line; the question is only **who else hears it**.

## Who already answers it

| The part | Already owned by |
|---|---|
| when a login fell below the person's percent, once, again after it climbs back | `QuotaAlerts` |
| when a login's status got worse under the policy | `StatusAlerts` ([design](../status-alerts/design.md)) |
| what a quota alert says on this Mac | the Notifications destination |

So a webhook is a **destination**, like Notify! and the Mac's notifications:
it decides nothing about quota. It is told every alert, and it says whether it
wants it.

## The words

| The screen prints | Means |
|---|---|
| *Webhooks* | the card in Settings → Sync & Alerts, below *Quota alerts* |
| *Webhook* | one URL the person owns, with how and what it is sent |
| *Name* | what the list shows; the URL's host until the person types one |
| *URL* | where it is sent — a secret |
| *Slack* · *JSON* | the channel: a Slack incoming-webhook message, or a JSON body |
| *Every login* · a provider's name | the scope: every login, or every login of one product |
| *Quota alerts* · *Status alerts* | what it sends: the person's percents, and a status that got worse |
| *Send a test* | POST a message labelled as a test, never an alert |
| *Sent 2m ago* · *Failed — 404* · *Nothing sent yet* | the last delivery |

## The tree

```
QuotaMonitor.onRefreshed(login) ─┬─► QuotaAlerts   ─► .quota(QuotaAlert)
                                 └─► StatusAlerts  ─► .status(StatusAlert)
                                                         │
Alert = .quota | .status            (names the login by lineupName, and its provider id)
                                                         │
AlertDestination.announce(_ alert)  ◄────────────────────┘   every alert, every destination
   ├─► Notifications                 this Mac; today's wording
   └─► Webhooks  ◆                   the person's list, @Observable, in Alerting
         └─ Webhook ◇
              id · name · channel (slack | json) · scope (everyLogin | provider(id))
              sends (quotaAlerts, statusAlerts) · isOn
              wants(alert) → Bool
              delivery: neverSent | sent(at) | failed(Failure)
              │
              ├─ WebhookBody(alert | test, channel) → bytes
              └─ WebhookAddress ◇   the URL; https, or http to loopback / LAN only
                    │
                    ▼
              WebhookClient   one POST: same-origin redirects, a timeout, nothing secret logged

Saved:   settings.json  alerting.webhooks       ← WebhookSettingsRepository (JSONSettingsRepository)
Secrets: DestinationSecrets  webhook-url-<id>  ← one Keychain-with-fallback, shared with Notify!
```

## The laws, one owner each

| Law | Owner |
|---|---|
| a login fell below the person's percent: tell once, again only after it climbs a point above | `QuotaAlerts` |
| a login's status got worse under the policy: tell once per worsening | `StatusAlerts` |
| every alert goes to every destination; a destination never decides *whether* a login is low | `AlertDestination` (the fan-out in the composition root) |
| a webhook wants an alert when it is on, the alert's kind is one it sends, and the alert's provider is in its scope | `Webhook.wants(_:)` |
| a webhook that is off keeps its place, its URL and its last delivery; turning off is not removing | `Webhook` · `Webhooks` |
| how an alert, or a test, reads in Slack and as JSON; a test is labelled a test and is never shaped like an alert | `WebhookBody` |
| a URL is https, or http only to a loopback or LAN host (`localhost`, `127.0.0.0/8`, `::1`, `10/8`, `172.16/12`, `192.168/16`, `*.local`); anything else is refused when it is added | `WebhookAddress` |
| one POST per alert, no retry; a redirect is followed only on the URL's own origin; a 2xx is *sent*, anything else *failed* with its code; nothing that could carry the URL reaches a log or the pane | `WebhookClient` |
| the last delivery — an alert's or a test's — is the webhook's, kept in memory, shown in the pane | `Webhook.delivery` |
| a webhook's URL is a secret: in `DestinationSecrets`, never in `settings.json`, never in a log | `Webhooks` (writes it) · `DestinationSecrets` (keeps it) |
| a secret the Keychain refuses falls back to the app credential store, and the pane says so | `DestinationSecrets` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `Alert` ◇ = `.quota(QuotaAlert)` \| `.status(StatusAlert)` | `Domain/Alerting` | what was decided, naming the login (`lineupName`) and its provider id | **new** |
| `QuotaAlert` ◇ | `Domain/Alerting/QuotaAlerts` | gains `providerId`, so a scope can be judged | **kept**, one field added |
| `StatusAlert` ◇ · `StatusAlerts` ◆ | `Domain/Alerting/StatusAlerts` | see [status alerts](../status-alerts/design.md) | **moved** out of the Monitor |
| `AlertDestination` (port, `@Mockable`) | `Domain/Alerting` | `announce(_ alert: Alert) async` — replaces `QuotaAlertAnnouncer` and `QuotaAlerter.alert` | **new** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | the Mac's notifications for both kinds, today's words; `requestPermission()` | **moved**: `NotificationAlerter` + `QuotaAlertNotifications` become one |
| `Webhooks` ◆ `@Observable` | `Domain/Alerting/Webhooks` | the list: `add(url:name:channel:scope:sends:) throws(Refusal)`, `edit`, `remove`, `turn(on:)`, `sendTest(_:)`; an `AlertDestination` | **new** (replaces `RuleSet` + `RuleEngine`) |
| `Webhook` ◇ | `Domain/Alerting/Webhooks` | one webhook's data and `wants(_:)`; its `delivery` | **new** (replaces `Rule`) |
| `WebhookAddress` ◇ | `Domain/Alerting/Webhooks` | parses the URL, refuses what isn't https or a local host, answers `host` | **new** |
| `WebhookBody` ◇ | `Domain/Alerting/Webhooks` | `(Alert or .test, channel) → Data` | **kept**, reshaped onto `Alert` |
| `WebhookSending` (port) · `WebhookClient` | `Domain` · `Infrastructure/Alerting/Webhooks` | one POST, answers `Delivery` | **kept**, tightened |
| `WebhookSettingsRepository` (port) · `JSONSettingsRepository` | `Domain` · `Infrastructure/Settings` | `alerting.webhooks` in `settings.json` — a destination's own repository, like `NotifySettingsRepository` | **new** (replaces `JSONRuleRepository` and `rules.json`) |
| `DestinationSecrets` (port) · `KeychainDestinationSecrets` | `Domain/Settings` · `Infrastructure/Settings/Storage` | a destination's secret (Notify!'s token, a webhook's URL): `save` (verified read-back, else the fallback), `get`, `delete`, `isInKeychain(key)` | **new**: the fallback taken out of Notify!'s code in `JSONSettingsRepository`; Notify! and Webhooks both use it. Not DataSources' `DestinationSecrets`, the provider vault, which keeps provider keys and has no fallback |
| `SameOriginRedirectClient` | `Modules/DataSources` | a redirect never leaves the origin | **kept**, made public, named in DataSources' design |
| the Webhooks card | `App/Alerting/Webhooks` | renders the list and the form, tells `Webhooks`; its words live in the App | **new** (replaces `RulesPane`) |
| `QuotaMonitor` | `Domain/Monitoring` | drops `previousStatuses` and `alerter` | **changed**: smaller |
| `QuotaAlerter` | `Domain/Monitoring` | — | **removed** |

What a view never does: pick a login to test with, map an empty provider to
*every login*, or word an outcome in Domain. *Send a test* sends a test, so
it needs no login; the scope picker hands `.everyLogin` or `.provider(id)`.

## The flows

### Adding a webhook

The person pastes a URL, picks the channel, scope and what it sends, and
presses *Add*. `Webhooks.add` parses a `WebhookAddress` (a refusal comes back
as a `Refusal` the card prints: *Use an https URL — http is only for this Mac
or your network*), mints the id, writes the URL to `DestinationSecrets` under
`webhook-url-<id>` and the rest to `alerting.webhooks`. If the Keychain
refused, the card shows the fallback note, as Notify!'s does.

### A refresh

```
onRefreshed(login)
  quotaAlerts.review(login.id, named: login.lineupName, provider: login.providerId, usage: monitor.usage(of: login))
  statusAlerts.review(login.id, named: login.lineupName, provider: login.providerId,
                      status: monitor.status(of: login))
     each decided Alert ─► for destination in [notifications, webhooks]: await destination.announce(alert)

Webhooks.announce(alert)
  for webhook in list where webhook.wants(alert):          (concurrently; each with a 10 s timeout)
     body = WebhookBody(alert, webhook.channel)
     webhook.delivery = await client.post(body, to: secrets.address(webhook.id))
```

A paused login is never refreshed, so it never reaches either decider, and no
webhook hears of it.

### Send a test

`Webhooks.sendTest(id)` posts `WebhookBody(.test, channel)` — in Slack
*ClaudeBar test — this webhook works. No quota was judged.*, as JSON
`{"type":"test", …}` — and records the delivery like any other. It works
on a webhook that is off, since it is how the person checks one before
turning it on.

### Failing

One attempt, no retry, no queue. `delivery` becomes `failed(Failure)`:
`.status(404)`, `.timedOut`, `.unreachable`, `.redirectedAway`. The card
prints it with a *Send a test* button beside it; the log names the webhook's
id and the failure, never the URL. The alert is not sent again; the next
alert is.

## What is sent

| Field | Quota alert | Status alert | Test |
|---|---|---|---|
| `type` | `"quota"` | `"status"` | `"test"` |
| `provider` | `"claude"` | `"claude"` | `null` |
| `login` | `"Claude · work"` | `"Claude · work"` | `null` |
| `below` | `35` | `null` | `null` |
| `left` | `34` | `null` | `null` |
| `status` | `null` | `"critical"` | `null` |
| `was` | `null` | `"warning"` | `null` |
| `sentAt` | ISO 8601 | ISO 8601 | ISO 8601 |

Every key on every send, `null` where there is no value. Slack gets one line,
the same words the Mac's notification uses: *Claude · work is below 35% — 34%
left*, *Claude · work is critical — was warning*.

Nothing else leaves the Mac: no email, no prompt, no path, no session.

## Saved

```json
"alerting": {
  "webhooks": [
    { "id": "9F2C…", "name": "#ai-quota", "channel": "slack",
      "provider": null, "quotaAlerts": true, "statusAlerts": true, "isOn": true }
  ]
}
```

`provider: null` is *every login*. The URL is never here. Removing a webhook
removes its row and its secret. `delivery` is not saved: after a relaunch the
card says *Nothing sent since ClaudeBar started*.

## Not in it

- A percent per webhook — a webhook sends the person's quota-alert percents.
- Retries, a queue, or a send that waits across a relaunch.
- Discord, Teams, ntfy — each is a `WebhookChannel` case and a `WebhookBody`
  case when someone asks.
- Notify! as a target of quota alerts — Notify! publishes tiles, not alerts.
