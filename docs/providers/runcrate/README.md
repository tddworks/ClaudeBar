---
description: Show your Runcrate credit balance in dollars, using a Runcrate API key stored in the Keychain or an environment variable. Use when setting up Runcrate or when the connection test fails.
---

# Runcrate

Shows your remaining [Runcrate](https://runcrate.ai) credits as a dollar balance ("Credits"). There is no quota window or reset time, only the balance.

## Setup

1. Create an API key on the [Runcrate API keys page](https://runcrate.ai/dashboard/api-keys).
2. Settings → Providers → Runcrate → turn it on. It is **off by default**.
3. In **Settings**, paste the key into **API key** and press **Save**. Check it with **Test Connection** in **Runcrate Configuration**.
4. A second Runcrate account: **Accounts → Add Account** asks for that account's own API key.

**Environment variable:** instead of pasting a key, name an environment variable that holds it (the default is `RUNCRATE_API_KEY`). The variable is checked first; the saved key is used only when the variable isn't set. An added account uses only its own saved key.

## Permissions

- The pasted key is stored in the macOS **Keychain**, not in `~/.claudebar/settings.json`. **Clear** deletes it from the Keychain.
- The key is sent only to `api.runcrate.ai`.

## Gotchas

- **The balance never changes the status color.** There is no total to measure it against, so the card always counts as healthy and no low-balance notification fires. Keep an eye on the number itself.
- **"Authentication required"** means Runcrate answered 401 or 403. A brand-new key can take a moment to become active; wait and test again before replacing it.
- **The environment variable must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` isn't seen when the app starts from Finder or at login. Paste the key instead.
- **"Authentication required" right after pasting a key** can mean neither the variable nor a saved key was found. On a ClaudeBar you built yourself a locally built copy is ad-hoc signed and the Keychain can refuse it. Use the environment variable, or the released app.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [Runcrate dashboard](https://runcrate.ai/dashboard)
