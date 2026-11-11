---
description: UberLLM's definition, balance mapping, settings and account key isolation. Use when changing its connection.
---

# UberLLM: design

`Modules/Providers/Resources/Providers/uberllm.json` runs on the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names UberLLM.

## Source

`GET https://api.uberllm.dev/v1/balance` with `Authorization: Bearer <key>`, `Accept: application/json` and a 30-second timeout ([OpenAPI](https://uberllm.dev/openapi.json), `getBalance`). The answer:

```json
{"object": "balance", "balance_usd": 12.4, "held_usd": 0.35, "available_usd": 12.05, "saved_24h_usd": 1.18}
```

- `balance_usd`: the account's prepaid credit.
- `held_usd`: set aside for requests still running.
- `available_usd`: what new requests can use (`balance_usd` − `held_usd`).
- `saved_24h_usd`: optional, left out under a cent; not shown.

A bad key answers 401 with `{"error": {"type": "authentication_error", "code": "invalid_api_key", ...}}`, which is *Authentication required*; a 429 is a rate limit with its `Retry-After`; any other non-2xx is "HTTP error: N".

## Mapping

`available_usd` maps to `left: { money }` with **no ceiling**, so the card shows dollars and no percentage, and the balance never sets a status colour. It is the number that answers "can I still make requests", which is why it is shown instead of `balance_usd`. A number and a numeric string (`"7.50"`) are both read exactly, never through a `Double`; text that isn't a decimal amount (`"0x10"`, `"abc"`) is no balance, and a response with no `available_usd` fails at the mapping step.

## As data

| Setting | Kind · scope | Kept at | Used as |
|---|---|---|---|
| `apiKey` | secret · account | vault `provider.uberllm.apiKey` | `{"setting": "apiKey"}` |
| `authEnvVar` | text, default `UBERLLM_API_KEY` · provider | `uberllm.authEnvVar` | `{"environment": "{{setting.authEnvVar}}"}` |

The default login looks in the environment variable first, then its saved key. An added account's patch drops the environment variable, so it only ever uses its own key.
