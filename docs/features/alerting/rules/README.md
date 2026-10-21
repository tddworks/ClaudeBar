---
description: POST your quota to a webhook you own — a Slack channel, a script, a service — when a login falls below a percent, turns critical, or is depleted. Use when wiring quota into Slack or another endpoint.
---

# Rules

ClaudeBar's status alerts and [Quota alerts](../quota-alerts/README.md) tell *you* a quota is low, on this Mac. [Notify!](../notify/README.md) pushes it to your phone. **Rules** reach somewhere else: a URL you own — a Slack channel a team watches, a script on a home server, a monitoring service.

A rule is one sentence: **when** a quota crosses a line you pick, **then** POST to your URL. It runs after every refresh, on the logins you watch.

## Set up

Everything is in **Settings → Rules**.

1. Under **When**, pick a condition:
   - **Below** a whole percent (1–99) — the login's worst quota fell below it;
   - **Critical** — the worst quota is critical under your [status policy](../../../settings.md);
   - **Depleted** — the worst quota is empty.
2. Under **Then**, pick the payload: **Slack** or **JSON**.
3. Under **For**, choose **Every login** or one provider.
4. Paste your **Webhook URL** and press **Add Rule**.

Each rule then appears with its own card: a switch to turn it on or off, a **Configured** badge once a URL is saved, **Save URL** to replace it, **Try it** to fire once now, and **Remove**.

## When it tells you

- **Once per crossing.** A rule fires when a login meets its condition, and stays quiet while it stays there. It fires again only after the login climbs back out — for a percent, one whole point above your line (`Below 35` holds at 34% and stops at 35%).
- **The worst quota leads.** The rule judges the login's most severe quota first, then the lowest share — the same quota the menu bar would point at.
- **Per login.** Two Claude accounts are two things; each is judged and named on its own (*Claude · work*).
- Quotas you hid in the popover are left out. A prepaid balance with no ceiling has no percentage, so a **Below** rule never fires for it — but **Critical** and **Depleted** can.

**Try it** fires whatever the condition says, so you can prove a URL works before trusting it to a crossing.

## What it sends

**Slack** sends `{"text": "…"}` — one line, for an incoming webhook:

```json
{ "text": "Claude · work is below 35% — 28% left" }
```

**JSON** sends every field on every send, a `null` where there is no value:

```json
{
  "condition": "below",
  "login": "Claude · work",
  "percent": 35,
  "percentLeft": 28,
  "provider": "claude",
  "resetsAt": "2026-10-21T18:30:00Z",
  "ruleId": "…",
  "status": "warning",
  "window": "Session"
}
```

`status` is one of `healthy`, `warning`, `critical`, `depleted`. `resetsAt` is when the window refills, when the provider said.

## Privacy

The webhook URL is a **secret**: it can carry a token (`hooks.slack.com/services/…`, a signed URL, a private host). It is kept in the Keychain, never in `~/.claudebar/rules.json` and never in a log. Your rules themselves — condition, action, scope — are in `~/.claudebar/rules.json`.

What leaves the machine is the same handful of facts Notify! sends: the provider, the quota window's name, the remaining percent and the reset time. No prompts, no paths, no session content.

## Gotchas

- **Nothing arrives**: press **Try it** and read the sentence under the rule. A failure names the rule's id and the HTTP status in `~/Library/Logs/ClaudeBar/ClaudeBar.log`, never the URL.
- **One attempt, no retry.** A webhook that is down for a minute loses that crossing; the rule fires again the next time the login climbs back out and back in.
- **Told again after a restart**: a login still below your line is told once more after a relaunch, because what a rule already told you is remembered only while ClaudeBar runs.
- A **paused** login is never refreshed, so no rule judges it. Unpause it to bring it back.

## See also

[design.md](design.md) · [Quota alerts](../quota-alerts/README.md) · [Notify!](../notify/README.md) · [settings.md](../../../settings.md)