---
description: Track your OpenRouter credit balance (total credits minus usage, in USD) with an OpenRouter Management key. Use when setting up OpenRouter or when its key is rejected.
---

# OpenRouter

Shows your OpenRouter credit balance — total credits minus total usage, in USD. OpenRouter is pay-per-use, so there's no quota window or reset: the card shows the money left. When usage has met or overrun the balance, the card shows it as depleted.

## Setup

1. Create a **Management key** at [openrouter.ai/settings/management-keys](https://openrouter.ai/settings/management-keys). OpenRouter shows the credit balance only to a Management key; a regular API key from [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys) is refused with 403 ([OpenRouter's reference](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)). A Management key can't make completion calls, but it can create and delete your other keys: give it an expiry, and replace it before it expires. OpenRouter's Free plan has no Management keys; they come with its pay-as-you-go plans ([pricing](https://openrouter.ai/pricing)).
2. Settings → Providers → OpenRouter: turn it on. It's **off by default**.
3. In **Settings**, paste the key into **API key** and press **Save**, then **Test Connection** in **OpenRouter Configuration**.
4. A second OpenRouter account: **Accounts → Add Account** asks for that account's own API key.

**Environment variable:** instead of pasting a key, name an environment variable that holds it (the default is `OPENROUTER_API_KEY`). The variable is checked first; the saved key is used only when the variable isn't set. An added account uses only its own saved key.

## Gotchas

- **"OpenRouter shows credits only to a Management key …"** means OpenRouter answered 403: the key is a regular API key. Create a Management key (step 1) and paste that instead. If it still says so after you saved a Management key, the environment variable holds a regular key and is used first: unset it, or change **Environment variable** to a name that isn't set.
- **"Authentication required"** means OpenRouter answered 401: the key is wrong, deleted or expired. Check you copied the whole key and that it belongs to the account you funded.
- **"No data" after enabling** means neither the environment variable nor a saved key was found.
- **The environment variable must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login. Pasting the key is the reliable option.
- **The card shows DEPLETED** when your usage has met or exceeded your credits. The remaining amount (which can go negative) is still the balance OpenRouter reports.
- **Credits are always shown in USD** — that's the only currency OpenRouter bills in.
- **The key is stored in ClaudeBar's Keychain-backed vault.** **Clear** in Settings removes it. On a ClaudeBar you built yourself the Keychain can refuse an ad-hoc-signed build; use the environment variable, or the released app.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [OpenRouter Management keys](https://openrouter.ai/settings/management-keys)
