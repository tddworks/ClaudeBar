---
description: Track the Z.ai / Zhipu GLM Coding Plan 5-hour, weekly and MCP quotas, from a saved key or Claude Code's settings. Use when setting up Z.ai or when it shows "Key needed".
---

# Z.ai

Shows your GLM Coding Plan quota: the rolling 5-hour window, the weekly window, a monthly window on plans that have one, and MCP (tool) usage, each with its reset time. Token-based and credit-based plans (e.g. Coding Lite) both work.

## Setup

Paste your key, or let ClaudeBar read the one you already gave Claude Code.

- **Paste a key:** Settings → Providers → Z.ai → **API Key**, and pick the **Platform** it belongs to: Z.ai (`api.z.ai`), Zhipu (`open.bigmodel.cn`) or Zhipu dev (`dev.bigmodel.cn`). Claude Code doesn't need to be installed.
- **Use Claude Code's settings:** point Claude Code at Z.ai in `~/.claude/settings.json`, as Z.ai's own setup guide does:
  ```json
  {
    "env": {
      "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
      "ANTHROPIC_AUTH_TOKEN": "<your Z.ai API key>"
    }
  }
  ```
  A base URL on `open.bigmodel.cn` or `dev.bigmodel.cn` works too. ClaudeBar sends the quota request to the host it finds there.

Z.ai is on by default.

## Where the key comes from

In this order:

1. **API Key** saved in ClaudeBar, sent to the **Platform** you chose. It lives in the Keychain and is never logged.
2. **Claude settings file** (`~/.claude/settings.json` unless you choose another): `env.ANTHROPIC_AUTH_TOKEN` with `env.ANTHROPIC_BASE_URL`, else the first `providers` entry's `api_key` with its `base_url`. The key is used only when that URL's host is `api.z.ai`, `open.bigmodel.cn` or `dev.bigmodel.cn`, so a key meant for Anthropic or another gateway is never sent to Z.ai.
3. **Environment variable**: `ZAI_API_KEY`, or the name you set, sent to the chosen Platform. A name you set is also read from your login shell when the app's own environment lacks it ([#170](https://github.com/tddworks/ClaudeBar/issues/170)).

**Accounts → Add Account** adds another Z.ai login with its own key and platform. An added account never reads the settings file or the environment.

## Gotchas

- **A key exported only in `~/.zshrc` is found only under a name you set.** With the field left at `ZAI_API_KEY`, ClaudeBar reads its own environment only, which misses shell exports when it starts from Finder or Login Items. Type the variable's name to have your login shell asked too.
- **Only `ANTHROPIC_AUTH_TOKEN` is read from `env`.** A key stored as `ANTHROPIC_API_KEY` isn't found.
- **"Key needed" with a settings file means its URL isn't a Z.ai one.** The file's `ANTHROPIC_BASE_URL` (or first `providers` entry's `base_url`) must be on one of the three hosts, and the file must be valid JSON.
- **Old versions:** before 0.4.61 the weekly window was merged into the 5-hour one, and before 0.4.75 credit-based plans failed with "No recognized quota types found". Update if you see either.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
