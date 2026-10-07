# Grok: design

Contributor research for the Grok provider (`grok`, xAI Grok Build). User-facing setup is in [README.md](README.md). Added in #234 (0.4.75).

## As data

Grok is `ClaudeBarKit/definitions/grok.json` and `grok-billing.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it.

- **The login file holds several records**, keyed `<issuer>::<client-id>`. `jsonFile.record` picks the one that has a refresh token, then the one that expires last; a record with no expiry counts as never ending. Its fields are read inside that record, and a refreshed token is written back into it alone. `defaults` gives a record with no `oidc_issuer` the issuer `https://auth.x.ai`, which is never written back.
- **The refresh goes to the record's own issuer.** It is `{{issuer}}/oauth2/token` (no doubled slash when the issuer ends in `/`), with `client_id` only when the record names one. This is where the refresh token came from, recorded in the same file, so a definition cannot send it anywhere else. It refreshes 5 minutes before an ISO 8601 `expires_at`, never for a record with none, and once on a 401/403. An empty `refresh_token` in the answer never replaces the saved one.
- **Errors.** A rejected refresh or a still-rejected token gives the `grok login` hint. A record with no refresh token that is refused is *Key needed*, as for any API-key login (the old probe gave the hint).
- **Windows and money.** The period the server names is the quota's name and window: WEEKLY stays a weekly quota, MONTHLY and DAILY name theirs. With no period, the quota is "Usage" with no window, where the old probe guessed weekly. No usage reported is no quota, where the old probe showed 100%. The On-Demand cap's unit isn't stated, so it stays a share of the cap.
- **Accounts.** An added account is a folder holding its own `auth.json` (`path` setting); `requiresFiles` fails closed when it is gone.

## Source

Two `http.steps`, both with the same headers. `billing`: `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`, the billing endpoint the `grok` CLI itself calls. `settings` (optional, 5 s): `GET https://cli-chat-proxy.grok.com/v1/settings`, read only for the plan name; when it fails the usage still shows, but a 401/403 there is the login's, as for billing. The script receives `{ "billing": …, "settings": … }`. Headers: `Authorization: Bearer <access token>`, `Accept: application/json`, and `x-grok-client-mode: build`. 401/403 → `authenticationRequired`, which triggers one refresh-and-retry.

## Credentials: `~/.grok/auth.json`

A dictionary keyed by `"<issuer>::<client-id>"` (OIDC login) or a plain scope URL (legacy/API-key login):

```json
{
  "https://auth.x.ai::<client-id>": {
    "key": "<access token>",
    "auth_mode": "oidc",
    "email": "user@example.com",
    "refresh_token": "...",
    "expires_at": "2026-07-26T21:03:09.138930Z",
    "oidc_issuer": "https://auth.x.ai",
    "oidc_client_id": "<client-id>"
  }
}
```

- **Candidate choice** when several entries have a `key`: prefer one with a non-empty `refresh_token`, then the latest `expires_at` (a missing expiry counts as never expiring). An empty `refresh_token` counts as absent, so it neither wins selection nor triggers a refresh that can't work (e4a503b).
- **Timestamps** carry microsecond fractions (`.138930Z`) or `+00:00` offsets. `ISO8601DateFormatter` only takes milliseconds, so the fraction is trimmed to 3 digits before parsing.
- Entries without `expires_at` (API-key style) never refresh proactively.

## Refresh

- **Proactive**: when `expires_at` is less than 5 minutes away and a refresh token exists. A failed proactive refresh is logged and the old token is tried anyway, unless the failure was `sessionExpired`.
- **Reactive**: on 401/403 from billing, refresh once and retry; a second 401/403 → `sessionExpired(hint: "Run `grok login`…")`.
- `POST {oidc_issuer}/oauth2/token` (default issuer `https://auth.x.ai`), form-encoded `grant_type=refresh_token&refresh_token=…&client_id=…`. HTTP 400/401 → `sessionExpired`; only the OAuth `error` code is logged, never the body.
- The response's `access_token`, rotated `refresh_token` and `expires_in` are written back into **that entry only**, preserving every other entry and field (the file is shared with the CLI). Same pattern as the Codex API probe.

## Response

```json
{
  "config": {
    "currentPeriod": { "type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "...", "end": "..." },
    "creditUsagePercent": 96.0,
    "onDemandCap":  { "val": 0 },
    "onDemandUsed": { "val": 0 },
    "productUsage": [{ "product": "GrokBuild", "usagePercent": 84.0 }]
  }
}
```

- The payload may or may not be wrapped in `config`; both are read.
- `creditUsagePercent` is **used**. Remaining = `100 - used`, floored at −100 (over-limit stays visible as depleted).
- Period `type` → quota type: contains `MONTHLY` → Monthly, `DAILY` → Daily, otherwise weekly. `end - start` becomes the window duration for pace math; `end` is the reset for every quota.
- `productUsage[].product` is shown without the `Grok` prefix and with camelCase split (`GrokBuild` → "Build").
- Amounts come wrapped as `{"val": N}`. On-demand is only emitted when `onDemandCap.val > 0`.
- When there is no `currentPeriod`, `billingPeriodStart`/`billingPeriodEnd` give the reset and window; a start is never paired with the other period's end.
- `prepaidBalance.val` is USD cents (`{}` means zero). A balance above zero shows as a **Prepaid** money quota; an empty wallet is left out, so it never reads as depleted.
- The plan badge is `subscription_tier_display` from the settings step, else `subscriptionTier` from billing; `SUPERGROK_HEAVY`/`supergrok` read as SuperGrok Heavy / SuperGrok.
- **Empty but valid** (99cb779): billing can return 200 with a `currentPeriod` and no percentages (fresh period, unmetered plan). That yields one 100%-remaining quota for the period instead of an empty grid. A response with no period at all still yields no quotas.
