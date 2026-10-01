---
description: Track MiniMax Coding Plan requests left per model, with an API key, on the International (minimax.io) or China (minimaxi.com) platform. Use when setting up MiniMax or when it shows an auth or HTTP error.
---

# MiniMax

Shows your MiniMax Coding Plan quota for the current interval: one row per model, with "used/total requests" and the time the interval ends.

## Setup

1. Get an API key from the MiniMax platform. **Open MiniMax API Keys** in the settings card opens the right page for the selected region.
2. Settings → Providers → MiniMax → turn it on. It is off by default.
3. In **MiniMax Configuration**:
   - **REGION**: International (minimax.io) or China (minimaxi.com). **The default is China**, so international accounts must switch it.
   - **API KEY**: paste the key, then press **Save & Test Connection**.

## Where the key comes from

The key is looked up in this order, as the card's **API KEY LOOKUP ORDER** note says:

1. An environment variable: `MINIMAX_API_KEY`, or the name you type in **API KEY ENV VAR (ALTERNATIVE)**.
2. The key saved in **API KEY**.

**Remove API Key** deletes the saved key. The saved key is kept in the app's UserDefaults credential store, not in `settings.json`.

## Gotchas

- **Check the region first when a valid key fails.** International and China are separate platforms with separate keys, and ClaudeBar only calls the one selected. The region was hard-wired to China before 0.4.38 ([#125](https://github.com/tddworks/ClaudeBar/issues/125)), and China is still the default.
- **The environment variable wins over the saved key.** If a `MINIMAX_API_KEY` in ClaudeBar's environment is stale, the key you pasted is never used.
- **Environment variables must be in ClaudeBar's own environment**, not just your shell's. Started from Finder, the Dock or Login Items, ClaudeBar doesn't see what `~/.zshrc` exports. Use the **API KEY** field, or `launchctl setenv MINIMAX_API_KEY <key>` and restart ClaudeBar.
- **A model showing 0% while the MiniMax dashboard shows plenty left** may be a response with no request counts. The probe only reads counts, not percentages; see [design.md](design.md).
- **"MiniMax API error: …"** is MiniMax's own `status_msg`, passed through unchanged.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
