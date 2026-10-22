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
> **Status: BUILT.** Mockup: [design-concept/webhooks](../../../../design-concept/webhooks/index.html);
> as built: [as-built.png](../../../../design-concept/webhooks/as-built.png).
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
| *Sent 2m ago* · *Sending…* · *Failed — 404* · *Nothing sent yet* | the last delivery |

## The tree

```
QuotaMonitor.onRefreshed(login) ─┬─► QuotaAlerts   ─► .quota(QuotaAlert)
                                 └─► StatusAlerts  ─► .status(StatusAlert)
                                                         │
Alert = .quota | .status            (names the login by lineupName, and its provider id)
                                                         │
AlertDestinations([…]).announce(_ alert) ◄───────────────┘   every alert, every destination
   ├─► Notifications                 this Mac; today's wording
   └─► Webhooks  ◆                   the person's list, @Observable, in Alerting
         └─ Webhook ◇
              id · name · channel (slack | json) · scope (everyLogin | provider(id))
              sends (quotaAlerts, statusAlerts) · isOn
              wants(alert) → Bool
              host · delivery: neverSent | sending | sent(at) | failed(Failure, at)
              │
              ├─ WebhookBody(alert | test, channel) → bytes
              └─ WebhookAddress ◇   the URL; https, or http to loopback / LAN only
                    │
                    ▼
              WebhookClient   one POST: same-origin redirects, a timeout, nothing secret logged

Saved:   settings.json  alerts.webhooks         ← WebhookSettingsRepository (JSONSettingsRepository)
Secrets: DestinationSecrets  webhook-url-<id>  ← one Keychain-with-fallback, shared with Notify!
```

## The laws, one owner each

| Law | Owner |
|---|---|
| a login fell below the person's percent: tell once, again only after it climbs a point above | `QuotaAlerts` |
| a login's status got worse under the policy: tell once per worsening | `StatusAlerts` |
| every alert goes to every destination; a destination never decides *whether* a login is low | `AlertDestinations` (the one fan-out both deciders tell, built in the composition root) |
| a webhook wants an alert when it is on, the alert's kind is one it sends, and the alert's provider is in its scope | `Webhook.wants(_:)` |
| a webhook that is off keeps its place, its URL and its last delivery; turning off is not removing | `Webhook` · `Webhooks` |
| how an alert, or a test, reads in Slack and as JSON; a test is labelled a test and is never shaped like an alert | `WebhookBody` |
| a URL is https, or http only to a loopback or LAN host (`localhost`, `127.0.0.0/8`, `::1`, `10/8`, `172.16/12`, `192.168/16`, `*.local`); anything else is refused when it is added | `WebhookAddress` |
| one POST per alert, no retry, a 10 s timeout; a redirect is followed only on the URL's own origin; a 2xx is *sent*, anything else *failed* with its code; nothing that could carry the URL reaches a log or the pane | `WebhookClient` |
| the last delivery — an alert's or a test's — is the webhook's, kept in memory, shown in the pane | `Webhook.delivery` |
| a webhook's URL is a secret: in `DestinationSecrets`, never in `settings.json`, never in a log | `Webhooks` (writes it) · `DestinationSecrets` (keeps it) |
| a secret the Keychain refuses falls back to the app credential store, and the pane says so | `DestinationSecrets` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `Alert` ◇ = `.quota(QuotaAlert)` \| `.status(StatusAlert)` | `Domain/Alerting` | what was decided, naming the login (`lineupName`) and its provider id | **built** |
| `QuotaAlert` ◇ | `Domain/Alerting/QuotaAlerts` | carries `providerId`, so a scope can be judged | **built** |
| `StatusAlert` ◇ · `StatusAlerts` ◆ | `Domain/Alerting/StatusAlerts` | see [status alerts](../status-alerts/design.md) | **built** |
| `AlertDestination` (port, `@Mockable`) · `AlertDestinations` | `Domain/Alerting` | `announce(_ alert: Alert) async`; `AlertDestinations` tells each destination in turn, and is what `QuotaAlerts` and `StatusAlerts` are handed | **built** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | the Mac's notifications for both kinds, today's words; `requestPermission()` | **built** |
| `Webhooks` ◆ `@Observable` | `Domain/Alerting/Webhooks` | the list: `add(url:name:channel:scope:sends:) throws(Refusal)`, `edit(_:url:name:channel:scope:sends:)` (`url` nil keeps it), `remove(_:)`, `turn(_:on:)`, `sendTest(_:)`, `urlsAreOutsideKeychain`; an `AlertDestination` | **built** |
| `Webhook` ◇ | `Domain/Alerting/Webhooks` | one webhook's data and `wants(_:)`; its `host` and `delivery`, never saved | **built** |
| `WebhookAddress` ◇ | `Domain/Alerting/Webhooks` | parses the URL, refuses what isn't https or a local host, answers `host` | **built** |
| `WebhookBody` ◇ | `Domain/Alerting/Webhooks` | `WebhookBody(.alert(_) \| .test, channel:, sentAt:).encoded() → Data` | **built** |
| `WebhookSending` (port) · `WebhookClient` | `Domain` · `Infrastructure/Alerting/Webhooks` | `post(_:to:webhook:) → WebhookPost` (`.sent` \| `.failed(WebhookFailure)`): one POST | **built** |
| `WebhookSettingsRepository` (port) · `JSONSettingsRepository` | `Domain` · `Infrastructure/Settings` | `alerts.webhooks` in `settings.json` — a destination's own repository, like `NotifySettingsRepository` | **built** |
| `DestinationSecrets` (port) · `KeychainDestinationSecrets` | `Domain/Settings` · `Infrastructure/Settings/Storage` | a destination's secret (Notify!'s token, a webhook's URL): `save` (verified read-back, else the fallback), `get`, `delete`, `isInKeychain(key)`. Notify! and Webhooks both use the one `JSONSettingsRepository.destinationSecrets`. Not the provider vault (`SecretVault`), which keeps provider keys and has no fallback | **built** |
| `SameOriginRedirectClient` | `Modules/DataSources` | a redirect never leaves the origin; public, so `WebhookClient` sends under the same law | **built** |
| the Webhooks card · `WebhookForm` · `WebhookWords` | `App/Alerting/Webhooks` | renders the list and the form, tells `Webhooks`; its words live in `WebhookWords` | **built** |
| `QuotaMonitor` | `Domain/Monitoring` | refreshes; every alert follows through `onRefreshed` | **built** |

What a view never does: pick a login to test with, map an empty provider to
*every login*, or word an outcome in Domain. *Send a test* sends a test, so
it needs no login; the scope picker hands `.everyLogin` or `.provider(id)`.
Editing never shows the URL again: the field is empty, and an empty field
keeps the URL the webhook has.

## The flows

### Adding a webhook

The person pastes a URL, picks the channel, scope and what it sends, and
presses *Add*. `Webhooks.add` parses a `WebhookAddress` (a refusal comes back
as a `Refusal` the card prints: *Use an https URL — http is only for this Mac
or your network*; a webhook that ticks neither kind is refused too), mints
the id, writes the URL to `DestinationSecrets` under `webhook-url-<id>` and
the rest to `alerts.webhooks`. If the Keychain refused, the card shows the
fallback note, as Notify!'s does.

### A refresh

```
quotaAlerts.follow(monitor) · statusAlerts.follow(monitor)          (composition root)

onRefreshed(login)
  quotaAlerts.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                     usage: monitor.usage(of: login))
  statusAlerts.review(login.id, named: monitor.lineupName(of: login), provider: login.providerId,
                      status: monitor.status(of: login))
     each decided Alert ─► AlertDestinations([notifications, webhooks]).announce(alert)

Webhooks.announce(alert)
  for webhook in list where webhook.wants(alert):          (concurrently; each with a 10 s timeout)
     body = WebhookBody(alert, webhook.channel)
     webhook.delivery = await client.post(body, to: secrets.address(webhook.id), webhook: id)   // .sending meanwhile
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

One attempt, no retry, no queue. `delivery` becomes `failed(Failure, at:)`:
`.status(404)`, `.timedOut`, `.unreachable`, `.redirectedAway`, or `.noURL`
when the webhook's URL is no longer kept (nothing is sent). The card
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
"alerts": {
  "thresholds": [60, 35],
  "webhooks": [
    { "id": "9F2C…", "name": "#ai-quota", "channel": "slack",
      "provider": null, "quotaAlerts": true, "statusAlerts": true, "isOn": true }
  ]
}
```

`provider: null` is *every login*. The URL is never here. Removing a webhook
removes its row and its secret. `host` and `delivery` are not saved: the host
is read from the kept URL at launch, and after a relaunch the card says
*Nothing sent yet*.

## Not in it

- A percent per webhook — a webhook sends the person's quota-alert percents.
- Retries, a queue, or a send that waits across a relaunch.
- Discord, Teams, ntfy — each is a `WebhookChannel` case and a `WebhookBody`
  case when someone asks.
- Notify! as a target of quota alerts — Notify! publishes tiles, not alerts.
