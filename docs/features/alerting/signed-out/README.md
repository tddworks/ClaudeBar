---
description: The notification ClaudeBar sends once a login is signed out — "Claude · work signed out" with what to run — and how a webhook can send it too. Use when a sign-out arrives twice, never, or keeps coming back.
---

# Signed out

A CLI login is a sign-in, and sign-ins end: `claude` or `codex` asks you to
log in again, usually mid-run. When ClaudeBar's own refresh is refused
because the sign-in ended, it tells you once, right away: *Claude · work
signed out — Run `claude` in terminal to log in again.*

## When it tells you

- **Once per sign-out**, at the refresh that found it — not once per refresh.
- **Per login**, named as the menu names it: *Claude · work*.
- The text is the provider's own advice, the same the card shows under
  *Session expired.*
- **Signing in again clears it**: after the next successful refresh, a later
  sign-out is told again.
- A **paused** login is never refreshed, so it is never told.

ClaudeBar can't warn *before* a sign-in ends: no tool writes down when that
will be. The expiry some credential files carry is the access token's, which
renews itself every few hours.

## Somewhere else

A [webhook](../webhooks/README.md) with **Signed-out alerts** ticked sends the
same moment to Slack or your own URL. Webhooks saved before this existed send
nothing until you tick it.

## Gotchas

- **Nothing arrives**: allow ClaudeBar in **System Settings → Notifications**.
- **Told again after a restart**: a login still signed out is told once more
  after a relaunch — what was told lives in memory.
- **"Not signed in" never tells**: a login that was never signed in, or has no
  key, is setup, not a sign-out; the card says what to do.

## See also

[design.md](design.md) · [Status alerts](../status-alerts/README.md) · [Webhooks](../webhooks/README.md)
