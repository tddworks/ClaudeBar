---
description: Track your DeepSeek API account balance (paid and granted, in CNY or USD) with a DeepSeek API key. Use when setting up DeepSeek or when its key is rejected.
---

# DeepSeek

Shows your DeepSeek platform balance, split into paid (topped-up) and granted credit, in your account's currency. DeepSeek is pay-per-use, so there's no quota window or reset: the card shows the money left.

## Setup

1. Create an API key at [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) (the **Open DeepSeek API Keys** link in the card goes there).
2. Settings → Providers → DeepSeek: turn it on. It's **off by default**.
3. Click DeepSeek, paste the key into **API KEY** under **DeepSeek Configuration**, then **Save & Test Connection**.

Instead of pasting a key, you can put the name of an environment variable in **API KEY ENV VAR (ALTERNATIVE)** (default `DEEPSEEK_API_KEY`). ClaudeBar checks the variable first and falls back to the saved key.

## Gotchas

- **"Failed: DeepSeek rejected the API key. New keys may take a moment to activate."** DeepSeek answered 401 or 403. A key you've just created can take a moment to start working; otherwise check you copied the whole `sk-...` key.
- **"Failed: No API key found"** means neither the environment variable nor a saved key was found.
- **The environment variable must be in ClaudeBar's own environment.** It's read from the app process, so a variable exported only in `~/.zshrc` isn't seen when ClaudeBar starts from Finder or at login. Pasting the key is the reliable option.
- **The balance shows as EMPTY (0%)** when DeepSeek reports the balance can't be used for API calls (`is_available: false`), even if some money is left. The percentage is otherwise always 100%, because a balance has no cap.
- **Only one currency is shown.** If your account has balances in several currencies, ClaudeBar shows the first one DeepSeek lists, which is your billing currency (¥ for CNY accounts).
- **The key is stored in UserDefaults, not the Keychain.** **Remove API Key** in the card deletes it.

## See also

[troubleshooting](../../troubleshooting.md)
