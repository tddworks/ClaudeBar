---
description: Contributor design for SignedOutAlerts — the one owner of "a login's sign-in has ended", in Alerting beside QuotaAlerts and StatusAlerts, following the Monitor's refreshes and telling every alert destination once per sign-out.
---

# Signed out — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to journey moment
> 3b ([USER_JOURNEYS](../../../architecture/USER_JOURNEYS.md)): a login's
> sign-in ended, and nobody said so until the person opened the popover.
> [Webhooks](../webhooks/design.md) is the destination besides this Mac that
> hears it.
>
> **Status: BUILT.** User guide: [README.md](README.md).

## The person and the moment

Mia is mid-run when `claude` answers *please run /login*. ClaudeBar knew an
hour earlier: its own refresh was refused because the sign-in had ended, and
the card said *Session expired. Run `claude` in terminal to log in again.* But
the card is only read when the popover opens. She wants to be told once, when
it happens, named the way the menu names the login — and, with
[webhooks](../webhooks/README.md), her team's channel wants the same moment.

## What the data says

No credential store records when a sign-in ends. The only expiry a store
holds — Claude's `claudeAiOauth.expiresAt`, Grok's `expires_at`, read by
`refresh.oauth2.dueWhen` — is when the *access token* is renewed, hours away,
and is rewritten on every renewal. A forecast (*expires in 3 days*) has no
fact to stand on, so there is none.

What *is* known is the ending itself. A refresh fails with
`UsageError.sessionExpired(hint:)` when:

- the OAuth refresher is refused (`OAuth2Refresher`, the definition's `hint`), or
- a definition's error facts say so — `"http.401": { "sessionExpired": "…" }`.

The login keeps that failure as `lastError` (the card already prints it with
its hint, through `RefreshReport`). That kept fact is all this feature reads:
no credential lookup, no expiry, no new field on `Account`.

## Who answers it

```
QuotaMonitor  (refreshes; knows nothing after)
  │ onRefreshed(login)        a refresh that succeeded
  │ onRefreshFailed(login)    a refresh that failed — never a paused login's
  ├─► QuotaAlerts   ─► .quota(QuotaAlert)        (onRefreshed only)
  ├─► StatusAlerts  ─► .status(StatusAlert)      (onRefreshed only)
  └─► SignedOutAlerts ─► .signedOut(SignedOutAlert)
                            │
                            └─► AlertDestinations: Notifications · Webhooks
```

The Monitor learns nothing new: it tells whoever follows that a refresh
failed, as it tells them one succeeded. "Has this login's sign-in ended, and
was it told" has one owner, `SignedOutAlerts`; each destination words what it
is told; the login comes named as the lineup names it.

The card adds nothing: it already shows *Session expired.* and the hint from
`account.lastError`.

## The words

| The screen prints | Means |
|---|---|
| *Claude · work signed out* | the notification's title, the login as the lineup names it |
| *Run `claude` in terminal to log in again.* | the definition's hint; *Sign in again to see its usage.* when it has none |
| *Claude · work signed out: sign in again — Run `claude` …* | the Slack line; without the hint, just *… signed out: sign in again* |
| *Signed-out alerts* | the webhook's tick |

## The laws, one owner each

| Law | Owner |
|---|---|
| a sign-in has ended when a refresh fails with `sessionExpired` — the refresher refused, or a definition's error fact said so; nothing is guessed from an expiry instant | `SignedOutAlerts` (reading `Account.lastError`) |
| the Monitor tells its followers after a refresh that failed, as after one that succeeded; a paused login's refusal, or a fetch that landed after a pause, is never told | `QuotaMonitor.onRefreshFailed` |
| told once per sign-out: another failed refresh while still signed out is quiet | `SignedOutAlerts` |
| a refresh that succeeds with no error forgets the sign-out, so the next one is told again; any other failure in between keeps it | `SignedOutAlerts` |
| per login, never per product, named by its `lineupName` | `SignedOutAlerts` (handed the name, never looking it up) |
| each destination words the sign-out itself; Domain carries the hint, never a sentence | `Notifications` · `WebhookBody` |
| the memory is in memory: after a relaunch a login still signed out is told once more | `SignedOutAlerts` |
| an old saved webhook sends none of this until the person ticks it | `Webhook.Sends` · `JSONSettingsRepository` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `SignedOutAlert` ◇ | `Domain/Alerting/SignedOutAlerts` | `login` (lineupName), `providerId`, `hint` — the definition's, `nil` when it has none | **built** |
| `SignedOutAlerts` ◆ | `Domain/Alerting/SignedOutAlerts` | `review(_:named:provider:lastError:) async` — keeps which logins were told, decides, tells every destination; `follow(monitor)` hears both refresh outcomes | **built** |
| `Alert.signedOut` | `Domain/Alerting` | the third case a destination can be told | **built** |
| `QuotaMonitor.onRefreshFailed` | `Domain/Monitoring` | runs its observers after a failed refresh of an unpaused login | **built** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | words `.signedOut`: *Claude · work signed out*, the hint | **built** |
| `Webhook.Sends.signedOutAlerts` | `Domain/Alerting/Webhooks` | the kind, beside `recap`; a row saved before it reads `false` | **built** |
| `WebhookBody` | `Domain/Alerting/Webhooks` | `"type": "signedOut"` with `hint`; the Slack line | **built** |
| `WebhookWords.signedOutAlerts` · `WebhookForm` | `App/Alerting/Webhooks` | the tick and its hint | **built** |

## The flow

```
signedOutAlerts.follow(monitor)                       (composition root)

onRefreshFailed(login)  ·  onRefreshed(login)
  signedOutAlerts.review(login.id, named: monitor.lineupName(of: login),
                         provider: login.providerId, lastError: login.lastError)
    lastError is .sessionExpired(hint) → told already? quiet
                                       : tell once — destination.announce(.signedOut(SignedOutAlert(…)))
    lastError == nil                   → forget: the next sign-out is told again
    any other error                    → keep what was told
```

`QuotaAlerts` and `StatusAlerts` run on successful refreshes only and never
read this one: a sign-out is not a quota.

## Not in it

- A forecast before the sign-in ends — no store records when it will.
- A card line of its own — the card already prints the error and its hint.
- `authenticationRequired` (never signed in, no key) — that is setup, not a
  sign-in that ended; the card's *Sign in* covers it.
- A setting to mute it on this Mac — notifications are allowed or not in
  System Settings, as with [status alerts](../status-alerts/design.md#not-in-it).
- Remembering what was told across a relaunch.
- Notify!, live activity and status export surfaces.
