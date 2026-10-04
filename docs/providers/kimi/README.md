---
description: Track Kimi Code plan and 5-hour limits through the interactive kimi CLI or the Kimi web billing API. Use when setting up Kimi or when it shows "No quota data found" or "Key needed".
---

# Kimi

Shows your Kimi Code plan quota and 5-hour limit, with reset times. The CLI names the plan's period (weekly on legacy plans, monthly on new ones). The API also shows request counts; it names a weekly plan (Andante, Moderato or Allegretto) and shows any other as "Plan", since the response doesn't say its period.

## Setup

1. Install the Kimi Code CLI (`curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash`), run `kimi` once and sign in with `/login`. If you already use the older Python `kimi-cli`, ClaudeBar reads its `/usage` layout too.
2. Settings → Providers → Kimi: turn it on (it is on by default).
3. Optional: click Kimi, then **Kimi Configuration → Data fetching method** picks CLI or API, and **Region** picks the platform your account is on.

## Data sources

| Mode | Needs | Pick it when |
|---|---|---|
| CLI (default) | `kimi` on your login shell's `PATH`, signed in | Almost always |
| API | A browser signed in to the same platform as your account (Full Disk Access), or `KIMI_AUTH_TOKEN` | You don't want to run the CLI, or want request counts and the plan name |

There is no fallback between modes: the one you pick is the only one that runs.

## Region (API)

Kimi runs two separate platforms: **kimi.com** (China) and **kimi.ai** (international). Accounts, cookies and quotas are not shared between them. In Kimi's settings, pick the **Region** your account is signed in to — the API then talks to that platform's billing API, reads that platform's `kimi-auth` cookie, and the console link points there. The default is China (kimi.com).

## More than one account

**Accounts → Add Account** asks for what the active data source needs: on the API, a `kimi-auth` session token (copy it from your browser's cookies for kimi.com or kimi.ai) and its region; on the CLI, a separate folder you signed in to with `KIMI_SHARE_DIR=<folder> kimi` and `/login`. An account added for one data source isn't checked while the other is active.

## Permissions

- **Full Disk Access (API mode only).** API mode reads the `kimi-auth` cookie from your browsers' cookie stores, which macOS protects. Grant it in System Settings → Privacy & Security → Full Disk Access. CLI mode needs nothing.

## Gotchas

- **The API with no cookie shows nothing, not an error.** If ClaudeBar can't find a `kimi-auth` cookie for the selected region (or Full Disk Access is missing), Kimi is skipped silently. Sign in to kimi.com (or kimi.ai, if that's your region) in your browser, grant Full Disk Access, or switch to CLI mode.
- **`KIMI_AUTH_TOKEN` must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login.
- **"Run `kimi` and sign in with /login"** means the CLI answered `/usage` with "Authorization failed". Sign in again in a terminal.
- **"No quota data found in Kimi CLI output"** means `/usage` didn't print a quota line within 15 seconds. Run `kimi` in a terminal and check that you're signed in and `/usage` works there. The `/usage` layout changed twice since the probe shipped (kimi CLI 0.36, then 2.x); current ClaudeBar reads all three layouts, and runs the CLI in its own folder so the one-time "Trust this folder?" prompt can't eat the typed `/usage` — update ClaudeBar if you're on an older version.
- **A newly installed CLI can take up to two minutes to be noticed**, because ClaudeBar caches a "not found" result for that long.
- **"Key needed" on the API** means the platform rejected the cookie (HTTP 401/403). Sign in to the matching platform again in your browser (kimi.com or kimi.ai, per your Region setting).

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
