---
description: Show today's and yesterday's Mistral Vibe cost and token totals from Vibe's local session logs, plus the Vibe Coding Plan's percent used and reset time from chat.mistral.ai with a session cookie. Use when setting up Mistral or when its card is empty.
---

# Mistral

Shows how much you spent and how many tokens you used in **Mistral Vibe** today, next to yesterday. With a chat.mistral.ai session cookie, it also shows your **Vibe Coding Plan**: how much of it you have used and when it resets.

## Setup

1. Use Mistral Vibe at least once, so it has written session logs to `~/.vibe/logs/session/`.
2. Settings → Providers → Mistral → turn it on. It is off by default.
3. Keep Settings → General → **Daily Usage Cards** on (the default). Mistral's numbers only appear in those cards.
4. For the Vibe plan percentage and reset time, paste your chat.mistral.ai cookie: sign in to [chat.mistral.ai](https://chat.mistral.ai), copy the full `Cookie` request header of any request (DevTools → Network tab), and paste it into **Settings → Providers → Mistral → Cookie**. Or set `MISTRAL_CHAT_COOKIE` in ClaudeBar's environment. Without it, Mistral still shows daily spend and tokens.

No key needed; with no cookie there is no network access. With a cookie, ClaudeBar calls `chat.mistral.ai`'s own usage endpoint — nothing else, and the cookie is never logged.

## Gotchas

- **Only Vibe is counted.** Le Chat and the Mistral API used from other tools (OpenCode and the like) don't write Vibe logs, so their usage is missing. For account-wide spend, use the Mistral console.
- **Empty card with Daily Usage Cards off.** With the setting off, Mistral shows no numbers at all, because it has no quota bars.
- **ClaudeBar treats Mistral as unavailable until `~/.vibe/logs/session/` exists**, so it stays empty on a Mac where Vibe was never run.
- **A session counts on the day it started.** A session that begins before midnight and runs past it is counted entirely in the earlier day.
- **Cost is Vibe's own number** (`session_cost` in each session's `meta.json`). ClaudeBar doesn't apply its own pricing, so if Vibe's cost is off, ClaudeBar's is too.
- Session folders whose `meta.json` is missing or unreadable are skipped without an error.
- **The cookie is the full `Cookie` header**, not one cookie's value: the session cookie's exact name is Mistral's own (`ory_session_…`), so copy the whole header while it is fresh. ClaudeBar cannot lift the session cookie out of your browser by itself — cookie names are matched exactly, and Mistral's is not public — so a browser read finds at most `csrftoken`, which is not enough to sign in.
- **A cookie expires.** When chat.mistral.ai refuses it, Mistral's plan card asks you to sign in and paste a fresh one; the daily spend and tokens keep working.

## See also

[troubleshooting](../../troubleshooting.md) · [#496](https://github.com/tddworks/ClaudeBar/issues/496), where the Vibe plan usage came from — with the research from [#209](https://github.com/tddworks/ClaudeBar/pull/209)
