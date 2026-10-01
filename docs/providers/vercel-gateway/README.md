---
description: Show your Vercel AI Gateway credit balance in dollars, using an AI Gateway API key stored in the Keychain or an environment variable. Use when setting up Vercel Gateway or when the connection test fails.
---

# Vercel Gateway

Shows your team's remaining Vercel AI Gateway credits as a dollar balance ("AI Gateway Credits"). There is no quota window or reset time, only the balance.

## Setup

1. Create an API key in the Vercel AI Gateway dashboard (Settings has an **Open Vercel AI Gateway** link).
2. Settings → Providers → Vercel Gateway → turn it on. It is **off by default**.
3. Paste the key into **API KEY** and click **Save & Test Connection**. "Success: Connection verified" means it works.

**API KEY ENV VAR (ALTERNATIVE):** instead of pasting a key, name an environment variable that holds it (the default is `AI_GATEWAY_API_KEY`). The variable is checked first; the saved key is used only when the variable isn't set.

## Permissions

- The pasted key is stored in the macOS **Keychain**, not in `~/.claudebar/settings.json`. **Remove API Key** deletes it from the Keychain.

## Gotchas

- **The balance never changes the status color.** There is no total to measure it against, so the card always counts as healthy and no low-balance notification fires. Keep an eye on the number itself.
- **"Failed: Vercel rejected the API key. New keys may take a moment to activate."** Vercel answered 401 or 403. A brand-new key can take a moment to become active; wait and test again before replacing it.
- **The environment variable must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` isn't seen when the app starts from Finder or at login. Paste the key instead.
- **"Failed: No API key found"** means neither the variable nor a saved key was found. On a ClaudeBar you built yourself this happens even right after pasting a key: a locally built copy is ad-hoc signed, the Keychain refuses it, and there is no fallback store for this key. Use the environment variable, or the released app.

## See also

[troubleshooting](../../troubleshooting.md) · [Vercel AI Gateway dashboard](https://vercel.com/dashboard/ai-gateway)
