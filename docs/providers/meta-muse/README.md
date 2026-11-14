---
description: Track Muse Code session and weekly allowances through muse usage --json using your stored Meta login. Use when setting up Muse Code or when its usage is missing.
---

# Muse Code

See the Session and Weekly allowance left in your Muse Code subscription, their reset times and your tier. ClaudeBar runs `muse usage --json`; this command makes no model turn.

## Setup

1. Install Muse Code. The default macOS location is `~/.local/bin/muse`, which ClaudeBar's binary locator searches without a shell-profile change.
2. Sign in through `muse login`, then check `muse usage --json` in Terminal.
3. Open **Settings → Providers → Muse Code** and check **Test Connection**. The provider is on by default.

Muse has no usage API. ClaudeBar uses only Muse's stored Meta login on this Mac. There is no API key to paste, HTTP fallback or Add Account form.

## What it shows

- **Session** and **Weekly** percentages left. Muse prints percentages used, so 1% used appears as 99% left.
- Reset times from Muse's millisecond timestamps, shown on your clock.
- The tier Muse reports, for example `Muse Code High Usage`.

Muse reports a subscription allowance, not a separate limit for each model. ClaudeBar does not infer token usage or cost from it.

## Gotchas

- **CLI not found: muse** means ClaudeBar cannot locate the binary. Check `command -v muse`. If you installed it outside the default `~/.local/bin` location, see [troubleshooting](../../troubleshooting.md).
- **Session expired** means the allowance response reports a sign-in failure. Follow Muse's hint or run `muse login` and refresh.
- **Muse usage: …** shows the reason and hint Muse returned instead of an allowance.
- **Unsupported Muse usage schema** means the CLI changed its JSON contract. The tested version is Muse Code 1.4.20 with schema version 1.
- **Session pace is unavailable.** Muse's JSON does not state the session window length. ClaudeBar keeps it unknown; the generic Session short label is still `5h`.

## Permissions

ClaudeBar starts `muse usage --json` on refresh. Muse handles its own login. ClaudeBar has no credential lookup for this provider and does not read Muse's login files.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
