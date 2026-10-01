---
description: Track Antigravity's Gemini and Claude-and-others quota pools (5-hour and weekly) from the running app or `agy` CLI, or from your stored sign-in when the app is closed. Use when setting up Antigravity or when it shows an error.
---

# Antigravity

Shows Google Antigravity's two shared quota pools: **Gemini**, and **Claude & others** (every model that isn't Gemini). Each pool has a 5-hour and a weekly window. In the menu bar they appear as "Gemini", "Gemini Weekly", "Claude" and "Claude Weekly". Older Antigravity builds that don't report pools show a quota for each model instead.

## Setup

1. Install [Antigravity](https://antigravity.google) (the desktop app or the `agy` CLI) and sign in.
2. Settings → Providers → Antigravity: turn it on (it is on by default). There are no other settings.

## How it reads your quota

ClaudeBar picks a source automatically on each refresh:

| Source | Used when | Needs |
|---|---|---|
| Local language server | The Antigravity app or `agy` is running | Nothing. ClaudeBar finds the process and calls its local API on `127.0.0.1` |
| Google Cloud Code | Nothing is running | The sign-in Antigravity / `agy` saved in your Keychain, while it's still valid |

## Permissions

- **Keychain.** When Antigravity isn't running, ClaudeBar reads its saved Google sign-in (Keychain item `gemini`, account `antigravity`) through `/usr/bin/security`. It only reads this item and never changes it. If macOS asks whether to allow access, allow it, or the quota won't show while the app is closed.

## Gotchas

- **"Session expired. Sign in to Antigravity or run `agy` again."** ClaudeBar doesn't refresh Antigravity's sign-in itself. Every time the app or `agy` runs, the saved token is renewed. Once it expires with nothing running, open Antigravity or run `agy` once.
- **"Command did not complete within the timeout" with the app closed** was a bug in 0.4.92 and earlier ([#301](https://github.com/tddworks/ClaudeBar/issues/301)): ClaudeBar treated "no Antigravity process" as a failure and never tried the Cloud Code fallback. It's fixed in the next release.
- **"Authentication required" while Antigravity is running** means ClaudeBar found the language server process but its command line had no `--csrf_token`. Restart Antigravity.
- **"Could not connect to Antigravity API"** means the process was found but none of its local ports answered. This usually happens while the app is still starting. Try again shortly.
- **Gemini CLI quota is separate.** The [Gemini](../gemini/README.md) provider tracks Gemini Code Assist quota from the `gemini` CLI's sign-in.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Gemini](../gemini/README.md)
