---
description: Show today's and yesterday's Mistral Vibe cost and token totals, read from Vibe's local session logs. No API key needed. Use when setting up Mistral or when its card is empty.
---

# Mistral

Shows how much you spent and how many tokens you used in **Mistral Vibe** today, next to yesterday. In the default Local Logs mode there's no percentage or reset time, only daily spend and tokens; Code API mode adds your Vibe plan usage.

## Setup

1. Use Mistral Vibe at least once, so it has written session logs to `~/.vibe/logs/session/`.
2. Settings → Providers → Mistral → turn it on. It is off by default.
3. Keep Settings → General → **Daily Usage Cards** on (the default). Mistral's numbers only appear in those cards.

No key, no network access and no permission prompts: ClaudeBar only reads the local log files.

## Code API mode (Vibe plan usage)

Settings → Providers → Mistral → Probe Mode → **Code API** shows your Vibe Coding Plan usage percentage from `chat.mistral.ai`, using your browser session cookie. Local Logs (above) stays the default.

1. Open [chat.mistral.ai](https://chat.mistral.ai) while logged in, then DevTools → **Network**.
2. Trigger any request, select it, and copy the full `Cookie` request header (it contains `ory_session_*`, `csrftoken`, `csrf_token_*`).
3. Export it as `MISTRAL_CHAT_COOKIE` (or the variable named in the Mistral config card) before launching ClaudeBar:
   ```bash
   # Session cookies are credentials. A leading space keeps this out of shell history.
    export MISTRAL_CHAT_COOKIE='ory_session_...=...; csrftoken=...; ...'
   open -a ClaudeBar
   ```

The cookie expires; when Code API mode stops working, log in again and copy a fresh one. A variable exported only in your shell profile is invisible when ClaudeBar starts from Finder or at login.

## Gotchas

- **Only Vibe is counted.** Le Chat and the Mistral API used from other tools (OpenCode and the like) don't write Vibe logs, so their usage is missing. For account-wide spend, use the Mistral console.
- **Empty card with Daily Usage Cards off.** With the setting off, Mistral shows no numbers at all, because it has no quota bars.
- **ClaudeBar treats Mistral as unavailable until `~/.vibe/logs/session/` exists**, so it stays empty on a Mac where Vibe was never run.
- **A session counts on the day it started.** A session that begins before midnight and runs past it is counted entirely in the earlier day.
- **Cost is Vibe's own number** (`session_cost` in each session's `meta.json`). ClaudeBar doesn't apply its own pricing, so if Vibe's cost is off, ClaudeBar's is too.
- Session folders whose `meta.json` is missing or unreadable are skipped without an error.

## See also

[troubleshooting](../../troubleshooting.md) · [#209](https://github.com/tddworks/ClaudeBar/pull/209)
