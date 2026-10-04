---
description: Vercel AI Gateway as data — its definition, credits mapping, settings, account key isolation and the keys it reads from before. Use when changing its connection or migrating credentials.
---

# Vercel Gateway: design

`Modules/Providers/Resources/Providers/vercel-gateway.json` runs on the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names Vercel.

## Source

`GET https://ai-gateway.vercel.sh/v1/credits` with `Authorization: Bearer <key>`, `Accept: application/json` and a 30-second timeout, as the old probe sent it. 401/403 is *Authentication required*; a 429 is a rate limit with its `Retry-After`; any other non-2xx is "HTTP error: N".

## Mapping

`balance` is the team's remaining credits, in US dollars. It maps to `left: { money }` with **no ceiling**, so the card shows dollars and no percentage, and the balance never sets a status colour. A number and a numeric string (`"7.50"`) are both read exactly, never through a `Double`; text that isn't a decimal amount (`"0x10"`, `"abc"`) is no balance, and a response with no balance fails at the mapping step. `total_used` is not shown.

The quota's kind changed from the old probe's time-limit "AI Gateway Credits" to a model quota of the same name; the card is the same.

## As data

| Setting | Kind · scope | Kept at | Used as |
|---|---|---|---|
| `apiKey` | secret · account | vault `provider.vercel-gateway.apiKey` | `{"setting": "apiKey"}` |
| `authEnvVar` | text, default `AI_GATEWAY_API_KEY` · provider | `vercel-gateway.authEnvVar`, read from the old `vercel.authEnvVar` until first saved | `{"environment": "{{setting.authEnvVar}}"}` |

The default login looks in the environment variable first, then its saved key. An added account's patch drops the environment variable, so it only ever uses its own key.

## Keys kept before

`ProviderVault`'s `legacyKeys` table moves the default login's key into `provider.vercel-gateway.apiKey` from the Keychain item the old card used (`vercel-ai-gateway-api-key`), or from the older UserDefaults entry `com.claudebar.credentials.vercel-api-key`. The old copies are removed only after the new one reads back. An added login never inherits them. `JSONSettingsRepository`'s `legacySettingKeys` table does the same for the environment variable's name.
