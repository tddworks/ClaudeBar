---
description: Track OpenCode Go rolling 5-hour, weekly and monthly usage from the opencode.ai usage API, or from the local opencode database when no API key is set. Also shows today's tokens from opencode's own database. Use when its numbers look off.
---

# OpenCode Go

Shows how much of your OpenCode Go plan is left in its three windows: the rolling 5-hour window, the weekly window and the monthly window, each with its reset time. Beside the quota cards, **Daily usage** shows today's tokens and spend read from opencode's own database, against yesterday.

## Setup

1. Install the `opencode` CLI and sign in to OpenCode Zen: `opencode auth login`, then pick **OpenCode Zen**. This stores the API key in opencode's `auth.json`.
2. Settings → Providers → OpenCode Go → make sure the switch is on (it is on by default).
3. A second OpenCode Go account: **Accounts → Add Account** asks for that account's API key, kept in your Keychain. It always uses the API, never this Mac's database.

There are no OpenCode-specific settings. ClaudeBar picks its source automatically.

## Data sources

ClaudeBar chooses the mode itself; there is no switch.

| Mode | Needs | Used when |
|---|---|---|
| API (preferred) | An OpenCode Zen API key: `OPENCODE_API_KEY`, or the `opencode-go` / `opencode` entry in `~/.local/share/opencode/auth.json` (or `$XDG_DATA_HOME/opencode/auth.json`) | A key is found. Numbers match the opencode.ai dashboard |
| Local database (fallback) | This Mac's opencode database (`~/.local/share/opencode/opencode.db`) | No key is found. Estimates usage from this Mac's opencode history. Works with OpenCode 1 and 2, and counts spend from before an upgrade |

## Daily usage

With Daily Usage Cards on (Settings → General), OpenCode Go shows today's tokens and cost from opencode's own database, read directly: every assistant message the database holds, whatever provider opencode drove — Zen, OpenCode Go, a custom endpoint — added up as one total. The cost is what opencode itself recorded, so it reads $0 for a provider that logs no cost. It's read when you open the popover. OpenCode 1 and 2 both work, and history from before an upgrade to 2 is counted too.

The same totals are what the [Leaderboard](../../features/leaderboard/README.md) shares when you tick OpenCode there.

## Gotchas

- **Local-database numbers are an estimate.** They only count opencode-go messages sent from this Mac, and show what's left of fixed limits in dollars ($12 per 5 hours, $30 per week, $60 per month). Sign in to Zen so the API mode is used if you work on more than one machine.
- **A rejected key doesn't fall back.** Once a key is found, ClaudeBar uses the API only. "Session expired" means the key was rejected (HTTP 401): run `opencode auth login` and pick OpenCode Zen again. "Subscription required" means the key has no Go subscription (HTTP 403).
- **`OPENCODE_API_KEY` must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` is not seen when the app is started from Finder or at login. The `auth.json` entry always works.
- **Nothing shows and there's no error:** no key was found and this Mac has no opencode database (`~/.local/share/opencode/opencode.db`), so ClaudeBar skips the provider.
- In local-database mode the weekly window runs Monday to Monday in UTC, and the monthly window starts on the day of your first opencode-go message, matching the dashboard.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Oh My Pi](../omp/README.md) also reports OpenCode Go accounts it is signed into
