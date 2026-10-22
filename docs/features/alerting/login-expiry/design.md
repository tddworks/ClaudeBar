---
description: Contributor design for LoginExpiryAlerts — the one owner of "a login's sign-in expires soon", in Alerting beside QuotaAlerts and StatusAlerts, following the Monitor's refreshes and telling every alert destination.
---

# Login expiry — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to the warning
> the person never had: a login's *sign-in itself* expiring — *Claude · work
> expires in 3 days* — which is not a quota window closing.
> [Webhooks](../webhooks/design.md) is the destination besides this Mac that
> hears it.
>
> **Status: BUILT.** User guide: [README.md](README.md).

## The person and the moment

Mia is mid-run when `claude` suddenly answers *please run /login*. The OAuth
grant behind the CLI reached its end and nobody said so. She wants a heads-up
days ahead — once per step, not once per refresh — named the way the menu
names the login. With [webhooks](../webhooks/README.md), her team's channel
wants the same moment.

## What the data says

Which sign-ins *have* a knowable expiry was read off the credentials
themselves, not guessed:

| Product | The sign-in's expiry | Where it is read |
|---|---|---|
| Claude | knowable — OAuth `expiresAt` in milliseconds | `~/.claude/.credentials.json` `$.claudeAiOauth.expiresAt`, or the Keychain item the definition names — declared by `refresh.oauth2.dueWhen` (`unit: "milliseconds"`, skew 300) |
| Grok | knowable — `expiresAt` as ISO-8601 | `{{account.directory}}/auth.json` `$.expires_at`, declared by `dueWhen` (`unit: "iso8601"`) |
| Codex | not knowable — `auth.json` has only `last_refresh`; the CLI re-signs by age | never warned |
| Gemini · Antigravity | not knowable — the CLI refreshes its sign-in silently | never warned |
| every API-key product | no expiry — a key does not time out | never warned |

Two rules follow. Only a credential whose definition *declares* how to read
its expiry — the `dueWhen` its OAuth refresh already uses — is knowable;
nothing is parsed by inventing a format. And a login's expiry is asked of
all its data sources: Claude's default source is the `cli` one, whose block
names no credential at all, while the expiry lives in the `api` source's
credential. The renewal an OAuth refresh writes back — a fresh `expiresAt`
in the store — is what clears the warning; no extra forgetting is needed.

## Who answers it

```
Provider.refresh  (fetches; a successful fetch has just looked at the credentials)
  │ noteLoginExpiry(earliest expiry the login's data sources read)
  │ onRefreshed(login)
  └─► LoginExpiryAlerts ─► .loginExpiry(LoginExpiryAlert)
                            │
                            └─► AlertDestinations: Notifications · Webhooks
```

The Monitor learns nothing new. "When does this sign-in end" has one owner,
`LoginExpiryAlerts`; the notification only words what it is told; the login
comes named as the lineup names it. The card reads the same decider, so the
*within 7 days* rule is written once.

## The words

| The screen prints | Means |
|---|---|
| *Claude · work Login Expiry* | the notification's title, the login as the lineup names it |
| *Login expires in 3 days* | calendar days from today; `0` is said as *expires today*, `1` as *tomorrow* |
| *Sign in again to renew it.* | what to do — the same advice the CLI would give |

## The laws, one owner each

| Law | Owner |
|---|---|
| a credential's expiry is read only as its definition declares (`dueWhen`); a lookup that names no expiry, or a store that holds none, says nothing — never a guess from a field name | `DataSource.credentialExpiry()` |
| a login's expiry is the earliest its own data sources can read; a source the login cannot reach is never asked (the [multi-account law](../../../architecture/CANONICAL_MODEL.md)) | `Provider.loginExpiry(of:)` |
| the expiry is noted only on a successful refresh — a failed one keeps what we saw; a paused login is never refreshed, so never noted | `Provider.refresh` · `Account.loginExpiresAt` |
| `expiresAt` is a non-secret companion of the token: the instant is logged and sent, never the token beside it | `DataSource` (unchanged scrubbing) |
| warn once per step — 7 days, 3 days, today; quiet between steps, and quiet when no step is reached | `LoginExpiryAlerts` |
| a new expiry instant resets the ladder (a renewal, a re-login); the same instant never tells twice | `LoginExpiryAlerts` |
| the past is quiet: a sign-in that already expired gets no warning — the CLI says so itself | `LoginExpiryAlerts` |
| a login with no knowable expiry is never told, and never shown a line | `LoginExpiryAlerts` |
| *within 7 days* is written once — the decider's step and the card's line read the same ladder | `LoginExpiryAlerts.warning(of:)` |
| the memory is in memory: after a relaunch the current step is told once more | `LoginExpiryAlerts` |
| days are calendar days on this Mac, `0` = today, never a timestamp dump | `LoginExpiryAlerts` · `LoginExpiryWords` |
| an old saved webhook sends none of this until the person ticks it | `Webhook.Sends` |

## The pieces

| Piece | Where | One job | |
|---|---|---|---|
| `LoginExpiryAlert` ◇ | `Domain/Alerting/LoginExpiryAlerts` | `login` (lineupName), `providerId`, `days` — `0` = today | **built** |
| `LoginExpiryAlerts` ◆ | `Domain/Alerting/LoginExpiryAlerts` | keeps each login's ladder, decides, tells every destination; `follow(monitor)` hears each refresh; `warning(of:)` is the card's read | **built** |
| `Alert.loginExpiry` | `Domain/Alerting` | the third case a destination can be told | **built** |
| `LoginExpiryWords` | `Domain/Alerting/LoginExpiryAlerts` | the days said aloud — *in 3 days*, *today*; one wording for the notification, the webhook and the card | **built** |
| `DataSource.credentialExpiry()` | `DataSources` | reads the credential's expiry instant the way the definition declares it | **built** |
| `Account.loginExpiresAt: Date?` ◇ | `Providers` | what we last saw — survives a failed refresh, forgotten when a refresh finds nothing | **built** |
| `Provider.loginExpiry(of:)` | `Providers` | the earliest of the login's reached data sources | **built** |
| `Notifications` | `Infrastructure/Alerting/Notifications` | words `.loginExpiry`: *Claude · work Login Expiry*, *Login expires in 3 days. Sign in again to renew it.* | **built** |
| `Webhook.Sends.loginExpiryAlerts` | `Domain/Alerting/Webhooks` | the third kind; old saved webhooks decode it `false`, so they send none of this until ticked | **built** |

## The flow

```
refresh(login) succeeds
  account.noteLoginExpiry(loginExpiry(of: login))     // earliest read; nil when none says
onRefreshed(login)                                    // loginExpiryAlerts.follow(monitor)
  loginExpiryAlerts.review(login, named: monitor.lineupName(of: login),
                           provider: login.providerId, expiresAt: login.loginExpiresAt)
    expiresAt == nil → forget, quiet                  // no knowable expiry
    days = calendar days from today to expiresAt
    days < 0 → quiet                                  // already expired
    step = [7, 3, 0].last { days <= $0 } else → quiet // before the first step
    told[step]? → quiet;  else tell once:
      destination.announce(.loginExpiry(LoginExpiryAlert(…)))  
```

`QuotaAlerts` and `StatusAlerts` run beside it on the same refresh; the three
never read each other — a quota warning and an expiry warning answer
different questions and can both arrive. Renewal clears everything without
a word: the fresh instant starts a ladder nothing has been told on.

## Not in it

- A setting to mute expiry warnings on this Mac — a webhook chooses its
  kinds; the Mac's notifications are allowed or not in System Settings, as
  with [status alerts](../status-alerts/design.md#not-in-it).
- A configurable ladder — 7 · 3 · today is the answer, not a preference.
- Remembering the ladder across a relaunch, or warning from persisted state
  without a refresh.
- Notify!, live activity and status export surfaces — they follow if the
  moment proves worth it.
- More products as their sign-ins become knowable: a definition's `dueWhen`
  is the only thing a product needs to join.
