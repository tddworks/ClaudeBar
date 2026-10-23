---
description: Post the weekly recap to your Slack or JSON webhooks each week — the same numbers as Last week on the All page's Recap card, sent once when your calendar's week turns. Use when the recap doesn't arrive or you want to stop it.
---

# Recap webhooks

Once a week, **what did all of it add up to?** is worth more than to you
alone: your team's channel can hear it too. Tick **Weekly recap** on a
[webhook](../webhooks/README.md), and every week — at your calendar's week
turn, usually Monday — ClaudeBar sends the week that closed to that webhook:
the total, how it compares with the week before, each provider's part, the
top model, the biggest day, what caching saved. The same numbers the
[Recap card](../../usage-history/recap/README.md) reads, from the same
local logs.

## Set it up

**Settings → Sync & Alerts → Webhooks → Add Webhook** (or **Edit** one you
have):

1. Paste the **URL** and pick the **channel**, as with any webhook.
2. Under **SENDS**, tick **Weekly recap** — alone or beside the alerts.
3. Press **Add**, then **Send a test** to check the URL.

The webhook's **For** (every login, or one provider) doesn't apply here: the
recap is one read across every provider, in one unit, so there is nothing to
scope.

## When it goes out

At the **first refresh after your calendar's week turns** — the week starts
where your Mac's calendar starts it (Monday for most, Sunday in the US), so
the recap lands within a refresh or two of that first midnight.

- **The Mac was off all Monday** (or all week): the recap goes out at the
  first refresh after you're back — the closed week's days are kept, so it
  still reads whole.
- **The Mac slept for weeks**: one recap on return, for the week that closed
  last. Never a backlog of missed weeks.
- **The week added up to nothing**: nothing is sent. Silence, not a message
  of zeros.
- **One per week, ever**: the sent week is remembered in `settings.json`, so
  relaunching never sends it twice.
- **You ticked Weekly recap mid-week**: the first recap comes at the next week
  turn. This week's recap already had its moment, whether or not a webhook
  heard it; only a fresh install sends the closed week at once.

It rides the same refreshes the alerts do — with background refresh off, it
waits for the first interactive refresh. Turning the popover's *Recap*
section off does not stop the webhook: the webhook's tick is the whole
choice.

## What it sends

**Slack** gets one message:

```
Weekly recap Nov 3–9: $12.34, +20% vs the week before. Claude 62% · Codex 38%.
Top model claude-sonnet-4-5 · biggest day Nov 5 · cache saved $1.02.
```

Parts the week doesn't have (a change, a top model) are left out.

**JSON** gets every field on every send, `null` where there is no value:

```json
{ "type": "recap", "unit": "cost", "total": 12.34, "change": 0.2,
  "weekStart": "2026-11-02T00:00:00Z", "weekEnd": "2026-11-08T00:00:00Z",
  "providers": [ { "provider": "claude", "name": "Claude", "value": 7.65, "share": 0.62 } ],
  "topModel": "claude-sonnet-4-5", "biggestDay": "2026-11-05",
  "cacheSavings": 1.02, "workingTime": 40800, "sessions": 34,
  "tokens": null, "sentAt": "2026-11-09T00:05:00Z" }
```

`unit` is `cost` or `tokens` — the same one-unit rule as the card: dollars
only when every provider you used can be priced. `workingTime` is seconds.

## Gotchas

- **No recap arrived**: was the closed week empty? Did a webhook that sends
  recaps exist before the week turned? (A webhook added mid-week hears the
  *next* week that closes — *Send a test* checks the URL now.) The card on
  the All page says what the week held.
- **Failed — 404** and friends: as with any webhook — see
  [webhooks](../webhooks/README.md#gotchas). One attempt, no retry; the next
  week is the next recap.
- **Recap off but alerts on**: untick *Weekly recap* on that webhook.
- **Privacy**: the URL stays a secret in the Keychain, as any webhook's. The
  recap itself carries the totals, the provider names as the menu shows them,
  the top model's name and the days — no path, no prompt, no session.

## See also

[design.md](design.md) — how the moment is decided, and its laws ·
[Webhooks](../webhooks/README.md) — the list, the URL, the deliveries ·
[Recap](../../usage-history/recap/README.md) — the card, and how the
numbers are worked out
