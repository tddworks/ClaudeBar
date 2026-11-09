---
description: Runcrate's definition, credits mapping, settings and account key isolation. Use when changing its connection.
---

# Runcrate: design

`Modules/Providers/Resources/Providers/runcrate.json` runs on the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names Runcrate.

## Source

`GET https://api.runcrate.ai/v1/credits` with `Authorization: Bearer <key>`, `Accept: application/json` and a 30-second timeout. The answer is an OpenAI-style key record with the account's balance beside it:

```json
{"data": {"label": "...", "usage": 0, "limit": null, "limit_remaining": null, "rate_limit": {"requests": null, "interval": "1m"}},
 "credits": {"balance": 29.0283091795, "currency": "USD"}}
```

401/403 is *Authentication required*; a 429 is a rate limit with its `Retry-After`; any other non-2xx is "HTTP error: N".

## Mapping

`credits.balance` is the account's remaining credits, in US dollars. It maps to `left: { money }` with **no ceiling**, so the card shows dollars and no percentage, and the balance never sets a status colour. A number and a numeric string (`"7.50"`) are both read exactly, never through a `Double`; text that isn't a decimal amount (`"0x10"`, `"abc"`) is no balance, and a response with no `credits.balance` fails at the mapping step. The per-key `usage` and `limit` are not shown.

## As data

| Setting | Kind · scope | Kept at | Used as |
|---|---|---|---|
| `apiKey` | secret · account | vault `provider.runcrate.apiKey` | `{"setting": "apiKey"}` |
| `authEnvVar` | text, default `RUNCRATE_API_KEY` · provider | `runcrate.authEnvVar` | `{"environment": "{{setting.authEnvVar}}"}` |

The default login looks in the environment variable first, then its saved key. An added account's patch drops the environment variable, so it only ever uses its own key.
