---
description: Track Kimi Code weekly and 5-hour limits through the interactive kimi CLI or the Kimi web billing API. Use when setting up Kimi or when it shows "No quota data found" or "Authentication required".
---

# Kimi

Shows your Kimi Code weekly limit and 5-hour limit, with reset times. API mode also shows the request counts and your plan (Andante, Moderato or Allegretto).

## Setup

1. Install the Kimi Code CLI (`curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash`), run `kimi` once and sign in with `/login`. If you already use the older Python `kimi-cli`, ClaudeBar reads its `/usage` layout too.
2. Settings → Providers → Kimi: turn it on (it is on by default).
3. Optional: click Kimi, then **Kimi Configuration → Probe Mode** picks CLI or API. Changing it refreshes Kimi straight away.

## Probe modes

| Mode | Needs | Pick it when |
|---|---|---|
| CLI (default) | `kimi` on your login shell's `PATH`, signed in | Almost always |
| API | A browser signed in to kimi.com (Full Disk Access), or `KIMI_AUTH_TOKEN` | You don't want to run the CLI, or want request counts and the plan name |

There is no fallback between modes: the one you pick is the only one that runs.

## Permissions

- **Full Disk Access (API mode only).** API mode reads the `kimi-auth` cookie from your browsers' cookie stores, which macOS protects. Grant it in System Settings → Privacy & Security → Full Disk Access. CLI mode needs nothing.

## Gotchas

- **API mode with no cookie shows nothing, not an error.** If ClaudeBar can't find a `kimi-auth` cookie (or Full Disk Access is missing), Kimi is skipped silently. Sign in to kimi.com in your browser, grant Full Disk Access, or switch to CLI mode.
- **`KIMI_AUTH_TOKEN` must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login.
- **"Failed to parse output: No quota data found in Kimi CLI output"** means `/usage` didn't print a Weekly or 5h line within 15 seconds. Run `kimi` in a terminal and check that you're signed in and `/usage` works there. kimi CLI 0.36 changed the `/usage` layout; ClaudeBar 0.4.92 and later read both layouts, so update ClaudeBar if you're on an older version.
- **A newly installed CLI can take up to two minutes to be noticed**, because ClaudeBar caches a "not found" result for that long.
- **"Authentication required" in API mode** means kimi.com rejected the cookie (HTTP 401/403). Sign in to kimi.com again in your browser.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
