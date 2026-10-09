---
description: Track Codex 5-hour and weekly limits through the codex app-server RPC or the ChatGPT backend API. Use when setting up Codex or when it shows "—", stale numbers or an error.
---

# Codex

Shows your OpenAI Codex rate-limit windows (usually the 5-hour session and weekly limits) with reset countdowns. API mode also shows your Codex credits balance when ChatGPT reports one. Separate preview buckets such as GPT-5.3-Codex-Spark appear as extra rows after your main windows.

## Setup

1. Install the [Codex CLI](https://github.com/openai/codex) and run `codex` once to sign in with your ChatGPT account.
2. Settings → Providers → Codex: turn it on (it is on by default).
3. Optional: in the same pane, **Codex Configuration → Data fetching method** picks RPC or API.

## Multiple accounts

Use **Accounts → Add Account** in the provider settings to add another ChatGPT login: sign in with your browser, or choose a Codex folder that's already signed in. Accounts are told apart by their ChatGPT account, so two workspaces under one email are two accounts. Each can be named and pinned separately in the menu bar. See [multiple accounts](../../features/multi-account/README.md) for setup and reconnect instructions.

## Data sources

| Mode | Needs | Pick it when |
|---|---|---|
| RPC (default) | `codex` on your login shell's `PATH` | Almost always |
| API | A ChatGPT sign-in saved in `~/.codex/auth.json` | You'd rather not start a `codex` process on every refresh |

RPC mode starts `codex app-server` for each refresh and asks it for your rate limits. If that fails it runs `codex` with `/status` and reads the screen instead. API mode calls the ChatGPT usage endpoint directly and refreshes the token in `~/.codex/auth.json` when it's more than 8 days old. Neither mode falls back to the other, so if one keeps failing, switch modes.

## CLI location

With only the Codex desktop app installed, ClaudeBar runs the `codex` inside it (`/Applications` or `~/Applications`); no separate CLI install is needed. A `codex` on your `PATH` comes first.

If ClaudeBar can't find the `codex` program, or finds a different one than you use, set **Settings → Providers → Codex → Configuration → CLI location**. Use **Choose…** to pick the program, or type its full path and press Return. The change takes effect immediately, for every account and for Add Account's sign-in. **Reset** goes back to finding `codex` on its own.

A shell alias or function (`alias c=…`) can't be used: ClaudeBar starts a program, not a shell. Run `which c` (or `type c`) in a terminal to see what the alias runs, and choose that. An alias that only points `codex` at another config folder is a second account, not a different program: add that folder in **Accounts → Add Account**.

## Gotchas

- **Codex login kept in the Keychain** (`cli_auth_credentials_store = "keyring"`): RPC mode works; click Refresh once after starting ClaudeBar. API mode needs `~/.codex/auth.json`, so it can't read a Keychain login ([#525](https://github.com/tddworks/ClaudeBar/issues/525)).
- **Sign in with ChatGPT, not an API key.** API mode reads only the OAuth tokens in `~/.codex/auth.json`. `OPENAI_API_KEY` isn't used. If the pane says "No OAuth credentials found", run `codex` and sign in.
- **"No rate limits available yet - make some API calls first"** means Codex hasn't reported a window for this account yet. Use Codex once, then refresh. Free plans without limits show 100% with "Free plan".
- **No countdown after a fallback.** When `app-server` fails and ClaudeBar reads the `/status` screen instead, it gets percentages but no reset times. Check the log for "Codex RPC failed".
- **The first window may be weekly.** Some plans report a weekly window as Codex's primary window. ClaudeBar uses the window's real length for pace and burn rate, but the card may still be labelled Session.
- **"Could not find usage limits in Codex output" on ClaudeBar before 0.4.84.** Newer Codex CLIs removed the `untrusted` approval policy that older ClaudeBar versions passed, so both paths failed ([#259](https://github.com/tddworks/ClaudeBar/issues/259)). Update ClaudeBar.
- **"Session expired. Run `codex` in terminal to log in again."** (API mode) means the refresh token was expired, reused or revoked. Sign in again with `codex`.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
