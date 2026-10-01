---
description: Track OpenCode Go rolling 5-hour, weekly and monthly usage from the opencode.ai usage API, or from the local opencode database when no API key is set. Use when setting up OpenCode Go or when its numbers differ from the dashboard.
---

# OpenCode Go

Shows how much of your OpenCode Go plan is left in its three windows: the rolling 5-hour window, the weekly window and the monthly window, each with its reset time.

## Setup

1. Install the `opencode` CLI and sign in to OpenCode Zen: `opencode auth login`, then pick **OpenCode Zen**. This stores the API key in opencode's `auth.json`.
2. Settings → Providers → OpenCode Go → make sure the switch is on (it is on by default).

There are no OpenCode-specific settings. ClaudeBar picks its source automatically.

## Probe modes

ClaudeBar chooses the mode itself; there is no switch.

| Mode | Needs | Used when |
|---|---|---|
| API (preferred) | An OpenCode Zen API key: `OPENCODE_API_KEY`, or the `opencode-go` / `opencode` entry in `~/.local/share/opencode/auth.json` (or `$XDG_DATA_HOME/opencode/auth.json`) | A key is found. Numbers match the opencode.ai dashboard |
| Local database (fallback) | `opencode` on your PATH | No key is found. Estimates usage from this Mac's opencode history |

## Gotchas

- **Local-database numbers are an estimate.** They only count opencode-go messages sent from this Mac, and they compare the summed cost against fixed limits ($12 per 5 hours, $30 per week, $60 per month). Sign in to Zen so the API mode is used if you work on more than one machine.
- **A rejected key doesn't fall back.** Once a key is found, ClaudeBar uses the API only. "Session expired" means the key was rejected (HTTP 401): run `opencode auth login` and pick OpenCode Zen again. "Subscription required" means the key has no Go subscription (HTTP 403).
- **`OPENCODE_API_KEY` must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` is not seen when the app is started from Finder or at login. The `auth.json` entry always works.
- **Nothing shows and there's no error:** no key was found and `opencode` isn't on the PATH, so ClaudeBar skips the provider.
- In local-database mode the weekly window runs Monday to Monday in UTC, and the monthly window starts on the day of your first opencode-go message, matching the dashboard.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Oh My Pi](../omp/README.md) also reports OpenCode Go accounts it is signed into
