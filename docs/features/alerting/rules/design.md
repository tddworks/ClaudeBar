---
description: Contributor design for Rules — the person's own condition on a quota status and their own webhook action, kept in rules.json and driven by onRefreshed. Covers the model, the six laws, the channels, privacy and what is deferred.
---

# Rules — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to journey moment 19
> — *tell me, where I already look* — beside Quota alerts and Notify!. The laws
> are the model's
> ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says which piece keeps them.
>
> **Status: BUILT** (this PR). User guide: [README.md](README.md).

## The question, and who already answers part of it

*When my quota drops below 35%, POST to this URL.*

The status alerts and *Quota alerts* already say a quota is low, beside you, on
this Mac. Notify! pushes to a phone. Neither reaches a URL the person owns: a
Slack channel a team watches, a script on a home server, a monitoring service.
That is a different destination with a different condition, so it is one of its
own — **Rules** — beside `QuotaAlerts` and the Notify! publication, never a new
switch on either.

It follows a refresh, so it is not the Monitor's: it observes through
`onRefreshed`, the way Quota alerts and In use do, and the Monitor does not
change.

## What this builds, and what it doesn't

Built: a rule whose **condition** is a quota status (`Below a percent`,
`Critical`, `Depleted`) and whose **action** is a **webhook** — a Slack message
or a generic JSON body — kept in `~/.claudebar/rules.json`, with its own
Settings pane.

Deliberately not built, each its own change and problem first:

- other **conditions** — pace, a budget or a cost, a failed fetch, a login with
  no usage yet;
- other **actions** — run a command, switch the login in use, Notify!;
- the remaining **channels** — Discord, ntfy, Teams, PagerDuty. A channel is a
  `WebhookBody` case, and only `slack` and `json` are written here;
- the **retry/backoff ladder** — one attempt per crossing, no retry, no queue.

The design below says where each of those lands so the deferral is a shape, not
an absence.

## The words

| The screen prints | Means |
|---|---|
| *Rules* | the pane |
| *When* / *Then* | the condition / the action |
| *Below*, *Critical*, *Depleted* | the conditions |
| *Webhook* | the action |
| *Slack* / *JSON* | the payload a webhook sends |
| *Webhook URL* | where it is sent — a secret |
| *Every login* / a provider's name | the scope |
| *Once, until it climbs back* | the throttle |
| *Try it* | fire now, whatever the condition says |

## The pieces

| Piece | One job | Changes when |
|---|---|---|
| `Rule` (`Domain`) ◇ | one person's condition, action, scope and throttle, as data | a new condition, action, scope or throttle appears |
| `RuleSet` (`Domain`) ◆ | the person's rules — `rules`, `add`, `update`, `remove`, `isOn` — saved | the rule for what a rule *is* changes |
| `RuleReading` (`Domain`) ◇ | a login's worst quota as the person sees it: the one quota a rule judges | the rule for which quota leads changes |
| `RuleEngine` (`Domain`) ◆ | after a refresh: which rules a login met, once, and again only after it climbs back; `tryIt` | the rule for when to say it changes |
| `WebhookBody` (`Domain`) ◇ | the channel's payload | a channel is added |
| `RuleRepository` (port, `Domain`) · `JSONRuleRepository` (`Infrastructure`) | the rules as `rules.json`, and the URL in the vault | where they are kept changes |
| `WebhookSending` (port, `Domain`) · `WebhookClient` (`Infrastructure`) | one POST to the URL the rule holds — the only `URLRequest` site | the transport changes |
| `QuotaMonitor+RuleLogins` (`App`) | a refreshed `Account` flattened to a `RuleLogin` | never |
| the composition root | `monitor.onRefreshed { login in … rules.review(…) }` | never for rules |

`monitor.usage(of:)` is the usage with the person's hidden quotas already left
out, so a rule never judges a quota nobody watches.

## The rules

| Rule | Why |
|---|---|
| says once when the login meets the condition, and again only after it climbs back out | a quota hovering at the line would otherwise POST on every refresh |
| for a percent, "out" is a whole point above: `below(35)` holds while `percent < 35` and stops at `percent >= 35` | the percent is the whole percent the person sees (floor), so one point of hysteresis falls out of it |
| the login's worst quota leads: the most severe status first, then the lowest share | the one quota the person would point at |
| a balance with no ceiling has no share and is never judged by a percent; a login with no share at all meets no percent condition | `Quota.left`: a balance has no percentage |
| a critical or depleted condition is read under the person's `StatusPolicy` | ONE status per quota, whatever the policy is |
| the rule names the login (*Claude · work*), never only the product | two Claude logins are two things (F11) |
| scope `everyLogin` judges every refreshed login; `provider(id)` only its product's | a rule about one provider must not fire for another |
| a paused login is never judged | the Monitor never refreshes one, so `onRefreshed` never runs for it |
| a rule that is off does nothing and keeps its place | turning one off is not deleting it |
| the URL is a secret | the vault, never `rules.json`, never a log |
| the fallback is read before the vault, and an empty fallback means *removed* | it holds the newest answer — the URL when the Keychain refused to store it, an empty tombstone when it refused to forget it; a Keychain ACL can allow reads while refusing updates and deletes, leaving an older URL readable in the vault |
| the membership is recorded before the POST is awaited | `review` is re-entrant at the await: two logins refreshed at once must each hear once, and a write that straddled the await would lose one and tell it twice |
| the POST keeps to the origin its URL named; a redirect that leaves it is not followed and its 3xx is the answer | the URL can carry a token, and the law is `NetworkClient`'s (CANONICAL §5) |

## The flows

### Adding a rule

`Rule` mints its own id; `RuleSet.add(_:webhookURL:)` saves the rule to
`rules.json` and the URL to the vault. Settings prints the rule; an edit
replaces it in place by id.

### A refresh

`onRefreshed` fires once per refreshed login. The App seam flattens the
`Account` to a `RuleLogin` — its id, its product's id, the lineup name, and the
usage with hidden quotas left out — and calls
`RuleEngine.review(login, under: monitor.statusPolicy)`. The engine builds the
`RuleReading`, keeps per-rule, per-login memory of who is *in*, and for each
rule in scope whose condition holds and which is not already in, asks
`WebhookSending` for the body. `tryIt` bypasses both the condition and the
memory, so the pane can prove a URL works before trusting it.

### Failing

One attempt. A failed POST logs the route, the status and the rule's id — never
the URL — and does not retry; the rule is left *in*, so it will not try again
until the login climbs back out and back in. That is the honest answer for a
one-attempt feature, and the ladder above is where retrying goes.

### Pausing

A paused login is never refreshed, so it is never reviewed and the engine has
nothing to forget. The law is `Account.isPaused`'s, kept by the Monitor; Rules
only has to not reopen it.

## Privacy

The webhook URL is a secret. It can carry a token — `hooks.slack.com/services/T…/B…/…`,
a signed URL, a private host — so it goes to the Keychain-backed credential
store under `CredentialKey.ruleWebhookURL(ruleId)`, with the same fallback
Notify! uses when an ad-hoc build's Keychain refuses (`save`, then read back;
on a refusal, the app credential store, still never the JSON file). The URL is
never logged and never written to `rules.json`; a failure logs the rule's id,
the provider and the HTTP status.

What leaves the machine is the same handful of facts Notify! sends: the provider
name, the quota window's name, the remaining percent and the reset countdown.
No prompts, no paths, no session content.

## Is it easy to change

- A new **condition** is a `Rule.Condition` case and one line where the engine
  reads it.
- A new **action** is a `Rule.Action` case, one port (`CommandRunning`,
  `RuleNotifying`, `AccountSwitching`), one implementation and one branch —
  the shape Notify! already has. No port is declared until its action exists.
- A new **channel** is a `WebhookChannel` case and one `WebhookBody` case;
  nothing else moves.
- A new **scope** or **throttle** is a case, and the engine reads it where the
  old ones are read.

## Considered and rejected

**A percent on the Quota alerts list.** Quota alerts already are a percent
delivered as a macOS notification. A rule is a different action for a different
destination, and folding them would give one list two meanings.

**Reuse the Notify! gateway for webhooks.** It reaches a phone through Notify!'s
own account, not an endpoint the person owns — which is the whole point of a
rule.

**Fire on every refresh while below.** Every refresh would POST for as long as
the quota stayed low. Once per crossing, with the climb-back, is the rule Quota
alerts already keeps, and the reason a *below* condition is a whole percent.

**Judge `percentRemaining`.** A balance is `100` there. `Quota.left` is the one
truth, and `RuleReading` follows it the way every other surface does.

**Store the URL in `rules.json`.** It is a secret, and the rules file is
plaintext on disk. The vault is where every other secret already lives.

**A `RuleNotifying`/`CommandRunning` port now.** Declaring a protocol with no
implementation is dead code. The action cases come with their ports.

## Open

- **Retry.** One attempt is honest but thin: a webhook that is down for a minute
  loses the crossing. A ladder with backoff is the next change, and it needs a
  place to keep a pending send across a relaunch.
- **Several actions per rule.** Today a rule is one action; a person may want
  Slack *and* a script for the same moment.
- **A rule that names a quota window.** Today the worst quota leads; a rule
  about the weekly window only is a condition this design leaves out.