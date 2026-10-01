---
description: Track Command Code 5-hour and weekly limits and your monthly credit balance, from the same API the cmd CLI's /usage uses. Use when setting up Command Code or when it shows "Session expired".
---

# Command Code

Shows your Command Code 5-hour and weekly windows with reset times, plus a **Credits** card with your remaining dollar balance (monthly plan credits plus purchased and free credits).

## Setup

1. Install the `cmd` CLI and run `cmd login`. This writes your API key to `~/.commandcode/auth.json`, which ClaudeBar reads.
   Or set `COMMAND_CODE_API_KEY` (also accepted: `COMMANDCODE_API_KEY`); it takes precedence over the file.
2. Settings → Providers → Command Code → make sure the switch is on (it is on by default).

ClaudeBar only needs the key; the `cmd` binary doesn't have to be on your PATH. There are no Command Code-specific settings.

## Gotchas

- **"Session expired. Run `cmd login` or set COMMAND_CODE_API_KEY."** means Command Code rejected the key (HTTP 401 or 403). The key doesn't expire on its own, so it was revoked or replaced: log in again.
- **The environment variable must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` isn't seen when the app starts from Finder or at login. `cmd login` always works.
- **Credits card without a percentage:** the percentage needs your plan's monthly allowance, which ClaudeBar knows only for the plans it recognises. On an unknown plan the card shows just the balance, and only when there are no 5-hour or weekly limits to show.
- **Nothing shows and there's no error:** no API key was found, so ClaudeBar skips the provider.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [commandcode.ai/usage](https://commandcode.ai/usage)
