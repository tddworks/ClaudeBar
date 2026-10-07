---
description: OpenRouter as data — its definition, credits mapping, settings, account key isolation and what it doesn't read. Use when changing its connection or its balance card.
---

# OpenRouter: design

`ClaudeBarKit/definitions/openrouter.json` runs on the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names OpenRouter. Ported from the Swift provider of issue #89, which followed the old DeepSeek probe.

## Source

`GET https://openrouter.ai/api/v1/credits` with `Authorization: Bearer <key>`, `Accept: application/json` and a 30-second timeout, as the old probe sent it. 401/403 is *Authentication required*; a 429 is a rate limit; any other non-2xx is an HTTP error at the fetch step.

## Mapping

`data.total_credits` and `data.total_usage` are lifetime amounts in USD; the balance is their **difference**, which the JSON mapping can't say, so `openrouter-credits.js` reads them with `decimalSubtract` (exact BigInt decimal, never a `Double`) and returns one quota:

- `type: "model", name: "Credits"` with `left: { money: remaining, currency: "USD" }` — **no ceiling**, so the card shows dollars and no percentage, and the balance never sets a status colour. At ≤ 0 the quota reads *depleted* (the old probe pinned `percentRemaining` at 100; the canonical model shows the money instead).
- `resetText` is `Total: $10.00 · Used: $3.50`, rounded to cents half-up with `decimalCents`.

Amounts arrive as strings; a number is tolerated and read through `String()` before the decimal math. A missing or non-object `data`, or an amount that isn't decimal text, fails at the mapping step; a response with no `data` is *no data*.

## As data

| Setting | Kind · scope | Kept at | Used as |
|---|---|---|---|
| `apiKey` | secret · account | vault `provider.openrouter.apiKey` | `{"setting": "apiKey"}` |
| `authEnvVar` | text, default `OPENROUTER_API_KEY` · provider | `openrouter.authEnvVar` | `{"environment": "{{setting.authEnvVar}}"}` |

The default login looks in the environment variable first, then its saved key. An added account's patch drops the environment variable, so it only ever uses its own key. Clearing the variable's name leaves its template unfilled, so no variable is read — the saved key alone answers.

The old probe read its key from UserDefaults (`com.claudebar.credentials.openrouter-api-key`) and its variable's name from `openrouter.authEnvVar`, but it never shipped, so there is nothing to migrate: no `legacyKeys` rows.

## What it doesn't read

Only `/credits` — no models, no generation activity, no per-model spend. The status page (`status.openrouter.ai`) is linked, not fetched.
