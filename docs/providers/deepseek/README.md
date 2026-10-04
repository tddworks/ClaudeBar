---
description: Track separate DeepSeek accounts and their paid/granted balances in CNY or USD. Set up API keys, rename accounts, or troubleshoot rejected keys.
---

# DeepSeek

Shows your DeepSeek platform balance, split into paid (topped-up) and granted credit, in your account's currency. DeepSeek is pay-per-use, so there's no quota window or reset: the card shows the money left.

## Setup

1. Create an API key at [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) (the **Open DeepSeek API Keys** link in the card goes there).
2. Settings → Providers → DeepSeek: turn it on. It's **off by default**.
3. Click DeepSeek, paste the key into **API KEY** under **Default Account**, then **Save & Test Connection**.

Instead of pasting a key, you can put the name of an environment variable in **API KEY ENV VAR (ALTERNATIVE)** (default `DEEPSEEK_API_KEY`). ClaudeBar checks the variable first and falls back to the saved key.

## Multiple accounts

In DeepSeek's **Accounts** card, choose **Add Account → Enter API key** and supply the other account's key. ClaudeBar tests the connection and lets you name it, for example **Personal** or **Work**. Each added account uses only its own saved key; it never uses the default account's key or environment variable.

Use the Accounts card to rename, pause, reorder, pin or remove a login. Removing an added account deletes its saved key from ClaudeBar and leaves the DeepSeek platform account alone. To replace an added account's key, remove it and add it again. **Default Account** settings always configure the original login.

## Gotchas

- **"Failed: DeepSeek rejected the API key. New keys may take a moment to activate."** DeepSeek answered 401 or 403. A key you've just created can take a moment to start working; otherwise check you copied the whole `sk-...` key.
- **"Failed: No API key found"** means neither the environment variable nor a saved key was found.
- **The environment variable must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login. Pasting the key is the reliable option.
- **"DeepSeek reports that this balance is unavailable for API calls."** means the API reported `is_available: false`. ClaudeBar surfaces the failure and keeps any previous successful snapshot. A balance has no percentage or refill window.
- **Only one currency is shown.** If your account has balances in several currencies, ClaudeBar shows the first one DeepSeek lists, which is your billing currency (¥ for CNY accounts).
- **Keys are saved in ClaudeBar's Keychain-backed vault.** Existing default-account keys are migrated from UserDefaults only after a verified secure write. If migration fails, the old login remains usable and its key is preserved. **Remove API Key** deletes the default key only if secure deletion succeeds; removing an added account deletes its own key.

## See also

[troubleshooting](../../troubleshooting.md)
