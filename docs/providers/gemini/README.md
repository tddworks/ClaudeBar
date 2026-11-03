---
description: Track Gemini Code Assist quota per model tier with the Gemini CLI's Google sign-in, for a Code Assist Standard/Enterprise license (individual tiers lost it 2026-06-18). Use when setting up Gemini or when it shows "Session expired" or 100% everywhere.
---

# Gemini

Shows the remaining Gemini Code Assist quota for each model tier (Pro, Flash, Flash Lite, plus any model ClaudeBar doesn't recognise), with reset times. The most-used tier is listed first.

## Setup

**Code Assist for individuals, Google AI Pro and Ultra can no longer sign in.** On 2026-06-18 Google stopped serving Gemini Code Assist for individuals, Google AI Pro and Google AI Ultra, in the Gemini CLI too, and removed **Login with Google** for them ([Google's notice](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)). The Gemini card still works for a Google account that holds a Gemini Code Assist Standard or Enterprise license, until those subscriptions [wind down](https://docs.cloud.google.com/gemini/docs/codeassist/sunset). The license is what counts, not the account type: an admin can assign one to a Gmail address as well as a Workspace one ([Google](https://docs.cloud.google.com/gemini/docs/codeassist/manage-licenses)). Workspace's AI Ultra Access add-on doesn't count: Google is removing it, and its Gemini CLI access, from 2026-07-07, or at an annual plan's next renewal ([Google](https://support.google.com/a/answer/16345165)). Without such a license, use the [Antigravity](../antigravity/README.md) card instead: Antigravity CLI replaced the Gemini CLI.

1. Install the [Gemini CLI](https://github.com/google-gemini/gemini-cli), run `gemini`, and choose **Login with Google** with the account that holds the license. This creates `~/.gemini/oauth_creds.json`.
2. Settings → Providers → Gemini: turn it on (it is on by default).

ClaudeBar doesn't run `gemini` on each refresh. It reads the CLI's saved sign-in and asks Google's Code Assist API for your quota. It runs `gemini` briefly only to refresh the sign-in once it has expired.

## More than one account

Sign in to another Google account in a separate folder with `GEMINI_CLI_HOME=<folder> gemini`, then **Accounts → Add Account** and choose that folder (the one holding `.gemini/oauth_creds.json`). ClaudeBar asks you to refresh it once by hand before it refreshes in the background, because renewing its login runs `gemini` in that folder.

## Gotchas

- **API-key or Vertex sign-in isn't supported.** Without `~/.gemini/oauth_creds.json`, Gemini is treated as unavailable. Sign in with Google in the CLI.
- **"Session expired. Google retired the Gemini CLI's Login with Google …"** means Code Assist refused the login, even after `gemini` tried to renew it. For an account without a Standard or Enterprise license that is the retirement above: switch to Antigravity. For a licensed account, run `gemini` once and sign in again.
- **"Authentication required"** means the saved token was rejected, and running `gemini` to renew it either failed or wasn't possible because `gemini` isn't on your login shell's `PATH`. Run `gemini` yourself once, then refresh.
- **No reset window is shown.** Google states when each quota resets, but not how long its window is, so ClaudeBar doesn't guess one (it used to assume 7 days).
- **One row per tier, not per model.** Google applies the same quota to several model IDs (e.g. `gemini-2.5-pro`, `gemini-3-pro-preview` and `gemini-3.1-pro-preview` go down together), so ClaudeBar shows them as a single "Pro" row.
- **Every model at 100%** usually meant ClaudeBar couldn't find your Code Assist project and Google returned placeholder numbers. ClaudeBar now looks the project up the way the Gemini CLI does, which works without a Google Cloud account ([#124](https://github.com/tddworks/ClaudeBar/issues/124)). If you still see it, check the log for the `project` step failing.
- **Antigravity is a separate provider.** Its Gemini quota is on the [Antigravity](../antigravity/README.md) card.
- **An added login needs a folder of its own.** The default login's folder and another listed login's are refused, `~` included. A path you type with `~` is saved as the full folder, because the CLI can't expand it.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Antigravity](../antigravity/README.md)
