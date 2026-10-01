---
description: Track Grok (xAI Grok Build) credit usage for the current billing period, per-product limits and on-demand spend, using the grok CLI's sign-in. Use when setting up Grok or when it shows "Session expired".
---

# Grok

Shows how much of your xAI credit allowance is left in the current billing period (weekly on most plans), how much each product has used (Build, Imagine, Voice), and on-demand overflow once you've set an on-demand cap. All share the period's reset countdown.

## Setup

1. Install xAI's `grok` CLI and run `grok login`. This writes `~/.grok/auth.json`, which ClaudeBar reads.
2. Settings → Providers → Grok → make sure the switch is on (it is on by default).

The `grok` binary doesn't need to be on your PATH; ClaudeBar only needs the sign-in file. There are no Grok-specific settings.

## Gotchas

- **ClaudeBar refreshes the sign-in and writes it back** to `~/.grok/auth.json` when the token is within 5 minutes of expiring or is rejected. The file is shared with the `grok` CLI; other entries in it are kept.
- **"Session expired. Run `grok login`…"** means the refresh token was rejected too. Run `grok login` again, then refresh.
- **Several sign-ins in `auth.json`:** ClaudeBar uses one that can be refreshed, and among those the one that expires last.
- **100% at the start of a period** is expected: when xAI reports a billing period but no usage figures yet, ClaudeBar shows the whole period as remaining rather than an empty card.
- **The On-Demand card only appears once you've set an on-demand cap** on your xAI account.
- **Nothing shows and there's no error:** `~/.grok/auth.json` is missing or holds no token, so ClaudeBar skips the provider.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [status.x.ai](https://status.x.ai)
