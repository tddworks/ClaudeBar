---
description: Show your MartLLM prepaid balance in dollars, using a MartLLM API key stored in the Keychain or an environment variable. Use when setting up MartLLM or when the connection test fails.
---

# MartLLM

Shows the part of your prepaid [MartLLM](https://martllm.com) credit that new requests can still use, as a dollar balance ("Credits"). There is no quota window or reset time, only the balance.

## Setup

1. Create an API key on the [MartLLM keys page](https://martllm.com/dashboard/keys).
2. Settings → Providers → MartLLM → turn it on. It is **off by default**.
3. In **Settings**, paste the key into **API key** and press **Save**. Check it with **Test Connection** in **MartLLM Configuration**.
4. A second MartLLM account: **Accounts → Add Account** asks for that account's own API key.

**Environment variable:** instead of pasting a key, name an environment variable that holds it (the default is `UBERLLM_API_KEY`). The variable is checked first; the saved key is used only when the variable isn't set. An added account uses only its own saved key.

## Permissions

- The pasted key is stored in the macOS **Keychain**, not in `~/.claudebar/settings.json`. **Clear** deletes it from the Keychain.
- The key is sent only to `api.martllm.com`.

## Gotchas

- **The number can dip and come back.** MartLLM sets money aside while a request is still running (a video or music job can take minutes) and releases what it didn't cost when it finishes. ClaudeBar shows what is left after that hold, so it can be a little below the balance on the [dashboard](https://martllm.com/dashboard) for a while.
- **The balance never changes the status color.** There is no total to measure it against, so the card always counts as healthy and no low-balance notification fires. Keep an eye on the number itself.
- **"Authentication required"** means MartLLM answered 401 or 403. Keys start with `ull_`; check you pasted the whole key.
- **The environment variable must be in ClaudeBar's environment**, not only your shell profile. ClaudeBar reads its own process environment, so a variable exported in `~/.zshrc` isn't seen when the app starts from Finder or at login. Paste the key instead.
- **"Authentication required" right after pasting a key** can mean neither the variable nor a saved key was found. On a ClaudeBar you built yourself a locally built copy is ad-hoc signed and the Keychain can refuse it. Use the environment variable, or the released app.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md) · [MartLLM dashboard](https://martllm.com/dashboard)
