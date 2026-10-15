# Rest when spent: design

One depleted login makes its whole product read DEPLETED: the product's status is the
worst across its watched logins, so one spent weekly window keeps the menu bar red for
days while every other login is fine. The answer chosen is *rest*, not a new status rule:
the spent login steps out of every judgement until its window ends, then steps back in
on its own.

## The one sentence

A login whose longest watched quota is spent rests — out of every judgement, its
product's status spared — until that quota's window ends; *Wake* ends the rest now and
the resting for that login for good.

## The words

| Word | Meaning |
|---|---|
| **Rest** | the app's hold on a login whose spent quota said when it refills |
| `restingUntil` | the fact on the login: the date the window ends; `isResting` reads it against the clock |
| **RESTING** | the page's group and the badge for logins resting — never PAUSED, which only the person's stop earns |
| **Wake** | the person's word: end the rest now, and exempt the login from resting again |
| exempt | the person's per-login no; the menu's *Rest When Spent* tick clears and sets it |

## The pieces

| Piece | Home | Its one job |
|---|---|---|
| `Rest` | `Modules/Providers` (beside `SwitchWhenLow`) | the opt-in policy: is it on, which logins it may rest, and the judgement after a refresh |
| `Account.restingUntil` · `isResting` · `isWatched` | `Account` | the fact, its persistence, and watching = enabled and not resting |
| `Accounts.resting` | `Accounts` | the third bucket beside `watched` and `paused` — pause wins when both hold |
| `UsageError.resting(until:)` | `Modules/Quotas` | the refusal, an outcome like `.paused`, never a failure |
| `ProductTab.resting` | `Sources/Domain` | the page's RESTING rows |
| `ProviderBadgeState.resting(until:)` | `Sources/Domain` | *RESTING* when every login rests |
| the `onRefreshed` observer | `ClaudeBarApp` (the composition root) | asks the policy to judge each landing |

## The rules

- **Two facts, one effect.** Resting is the app's, pausing the person's. Both keep a
  login out of every judgement — no refresh, no status, no alert, no menu-bar name —
  and the page says which one happened and until when. Pause wins when both hold.
- **Judge what the person sees**, as quota alerts already do: hidden quotas out, a
  balance with no ceiling never judged, shares only.
- **The longest window decides.** Among the login's visible share quotas, the one with
  the longest window is the one that may rest it — the weekly for Claude, Codex and
  Z.ai today, without a vendor name anywhere.
- **Spent means depleted** — 0% left, the ABSOLUTE law. No second, competing threshold.
- **Never rest what you can't wake.** The rest is until the quota's own `resetsAt`, and
  only when that date is in the future. A quota that cannot say when it refills never
  rests its login.
- **Waking is the window's alone.** `isResting` is read against the clock: when the
  window passes the login is watched again, the next refresh judges it afresh, and a
  fresh answer that is not spent clears the stored rest. Nothing is scheduled; nothing
  is fetched before.
- **The person's say.** *Wake* ends the rest now and exempts the login; an exempt login
  is never rested again while it is exempt. Unticking *Rest When Spent* is the same no.
- **The policy off drops every rest it holds** — the app's fact follows the app's
  policy — and keeps the exemptions.
- **Off until turned on**, like every policy here: the first *Rest When Spent* tick
  turns it on, per login.

## The flow

```
refresh lands ──▶ onRefreshed ──▶ Rest.review(login)
                                    │ hidden quotas out · shares only · longest window
                                    │ spent ∧ resetsAt in the future ∧ may rest
                                    ▼
                          login.restingUntil = resetsAt
                                    │
        lineup ──▶ watched loses it ──▶ no fetch, no status, no alert, no menu bar
                                    │
     page ──▶ RESTING group: name · until when · last seen · Wake
                                    │
                     window passes (read against the clock)
                                    ▼
                     watched again ──▶ refreshed ──▶ judged afresh
```

## Not in it (this slice)

- No Settings → Providers card section: the popover's login menu is the only door.
- No configurable threshold: spent means depleted; a second percent would be a second
  truth beside `StatusPolicy`.
- No notification: the RESTING row and the badge say it; the numbers return on their own.
- No moving of terminal sessions — *Switch when low*'s business; it now skips resting
  logins as targets.
- No quota-key picker: the longest window decides.

## Storage

Named settings under the provider, the `SwitchWhenLow` precedent (there is no bool kind
in `Setting.Kind`):

| Key | Holds |
|---|---|
| `<id>.restWhenSpent` | the policy's switch, off until a first tick |
| `<id>.restWhenSpentSkip` | the exempt account ids, comma-joined |
| `<providerId>.<acct>.restUntil` / `<id>.plainRestUntil` | a login's rest, epoch seconds |

## Invariants — each law, one owner

| Law | Owner |
|---|---|
| a login rests on the app's word, pausing on the person's; both keep it out of every judgement, the page says which and until when, and pause wins when both hold | `Account.restingUntil` · `ProductTab.resting` |
| the judgement is what the person sees: hidden quotas out, balances never judged, the longest window's share spent at 0 | `Rest.review` |
| a quota that cannot say when it refills never rests its login; the rest ends at its window's end, read against the clock, nothing scheduled | `Rest.review` · `Account.isResting` |
| *Wake* ends the rest now and the resting for that login; an exempt login is never rested again while exempt | `Rest.wake` |
| the policy off drops every rest it holds | `Rest.isOn` |
| a product whose every login rests reads *RESTING* — never PAUSED, which only the person's stop earns, and never NO DATA, for its quotas are simply spent | `ProviderBadgeState.resting` |

## Open questions

- A Settings card section for the policy, when the popover menu proves too hidden.
- A per-provider choice of quota key, if "longest window" ever picks wrong for someone.
