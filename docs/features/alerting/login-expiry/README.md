---
description: The heads-up ClaudeBar sends before a login's sign-in expires — "Login expires in 3 days" — and how a webhook can send it too. Use when an expiry warning arrives twice, never, or for a login that has no expiry.
---

# Login expiry

A CLI login is a sign-in, and sign-ins expire: `claude` asks you to log in
again every so often, mid-run, without warning. ClaudeBar reads the expiry
its own credential carries and gives you a heads-up first: *Claude · work
Login Expiry — Login expires in 3 days. Sign in again to renew it.*

## When it tells you

- **Once per step**: 7 days before, 3 days before, and on the day. Not once
  per refresh — nothing arrives again until the next step.
- **Per login**, named as the menu names it: *Claude · work*.
- Signing in again clears it: the fresh login starts a new countdown, and if
  it no longer expires soon nothing is said at all.
- A **paused** login is never refreshed, so it is never told. The menu bar
  turning red is quota business — an expiring sign-in never colours it.

## Which logins can warn

Only logins whose tool writes the expiry where ClaudeBar reads credentials:

- **Claude** and **Grok** warn.
- Codex, Gemini and Antigravity refresh their sign-ins silently — nothing to
  warn about, so nothing is said.
- API keys never expire — never warned.

## Somewhere else

A [webhook](../webhooks/README.md) with **Login expiry** ticked sends the
same moment to Slack or your own URL. Webhooks saved before this existed
send nothing until you tick it.

## Gotchas

- **Nothing arrives**: allow ClaudeBar in **System Settings → Notifications**.
- **Told again after a restart**: the current step is announced once more
  after a relaunch — the countdown lives in memory.

## See also

[design.md](design.md) · [Status alerts](../status-alerts/README.md) · [Webhooks](../webhooks/README.md)
