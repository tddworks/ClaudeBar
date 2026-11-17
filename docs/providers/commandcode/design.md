# Command Code: design

Contributor research for the Command Code provider (`commandcode`). User-facing setup is in [README.md](README.md). Added in ba390fc (2026-09).

## As data

Command Code is `Modules/Providers/Resources/Providers/commandcode.json` and `commandcode-credits.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it.

- **Fetch** — `http.steps`: `whoami` keeps `orgId` from `$.data.org.id` or `$.org.id`, `credits` calls `…/billing/credits?orgId={{orgId}}`, optional `subscriptions` calls `…/billing/subscriptions?orgId={{orgId}}` and keeps `periodStart` (`$.data.currentPeriodStart` or `$.currentPeriodStart`), and optional `summary` calls `…/usage/summary?orgId={{orgId}}&since={{periodStart}}`. `dropEmpty` leaves empty parameters out when there is none. The mapping script reads all available answers by name.
- **Key** — `COMMAND_CODE_API_KEY`, `COMMANDCODE_API_KEY`, `~/.commandcode/auth.json`'s `apiKey`, then a key saved in ClaudeBar (`apiKey`, account scope). An added account uses only its own saved key.
- **Errors** — `http.401` / `http.403` carry the `cmd login` hint; a 429 is a rate limit with its `Retry-After` (the old probe reported "HTTP error: 429"). 401/403/429 on optional steps still fails the fetch; 404/5xx/network errors on `subscriptions` or `summary` leave those answers absent so window quotas still render. A required step (`whoami`, `credits`) that answers something other than a JSON object fails at the mapping step with the old message.
- **Money** — the plan meter is `left: { money, of }`; an unknown plan's balance without an active `summary` spend total is money with no ceiling and no percentage (below, the probe's "fixed 100%" no longer applies).

## Sources

Four calls, mirroring the `cmd` CLI's `/usage` command, all with `Authorization: Bearer <API key>`:

1. `GET https://api.commandcode.ai/alpha/whoami?limits=1` → `org.id` and the account name (`user.userName`, else `user.name`).
2. `GET https://api.commandcode.ai/alpha/billing/credits?orgId=<org.id>` (no `orgId` when whoami returned none) → `credits` balances and `windowLimits`.
3. `GET https://api.commandcode.ai/alpha/billing/subscriptions?orgId=<org.id>` (optional) → active `status`, `planId`, `currentPeriodStart`, and `currentPeriodEnd`.
4. `GET https://api.commandcode.ai/alpha/usage/summary?orgId=<org.id>&since=<currentPeriodStart>` (optional) → `totalCost` for the billing period.

Any 2xx on required steps (`whoami`, `credits`) must be a JSON object or the call is a parse failure. 401/403 → `sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")`. There's no token refresh: the key is long-lived.

## API key lookup

1. `COMMAND_CODE_API_KEY`
2. `COMMANDCODE_API_KEY`
3. `apiKey` in `~/.commandcode/auth.json`, a flat `{ "apiKey": "user_..." }` written by `cmd login`

Environment variables come from the app's process environment.

## Credits and subscriptions response

```json
{
  "credits": {
    "monthlyCredits": 8.5, "purchasedCredits": 0, "freeCredits": 0
  },
  "windowLimits": {
    "fiveHour": { "used": 10, "cap": 40,  "resetAt": 1770000000000 },
    "weekly":   { "used": 50, "cap": 200, "resetAt": 1770500000000 }
  }
}
```

- Some deployments wrap payloads in `data` (the CLI reads `a.data`); both shapes are read for `whoami`, `credits`, `subscriptions`, and `summary`.
- `windowLimits.fiveHour` → session (5 h), `weekly` → weekly (7 d). Remaining = `(cap - used) / cap`; a window with no positive `cap` is skipped.
- `resetAt` and subscription period dates arrive as epoch **milliseconds**, epoch **seconds** or an ISO 8601 string. Numbers above 1e12 are treated as milliseconds.
- Numbers may be JSON numbers or numeric strings.

## Credits meter

`monthlyCredits` is treated as the **remaining** monthly allowance, not the allowance itself, so the cap comes from the active subscription's `planId` (falling back to legacy `credits.planId` when `subscriptions.status` is absent): a hard-coded map of plan-id prefix → monthly dollars (`planTotals` in the probe; e.g. `individual-go` / `individual-go-v1` $10, `individual-ultra` $300). It has to be updated by hand when Command Code changes its plans.

- The plan id is lowercased, `_` → `-`, and matched by prefix, **longest key first**, so `individual-pro-v1` doesn't match `individual-pro`.
- Remaining = monthly + purchased + free.
- Active plan in the table: Cap = max(plan allowance, monthly) + purchased + free; the `max` guards against a balance above the known allowance.
- Unknown plan on an active subscription with `summary.totalCost > 0`: Cap = `totalCost + remaining` (matching `cmd` CLI's `totalPool`).
- When `subscriptions.status` is present and not `"active"` (for example `"canceled"`), monthly plan allowances, `summary.totalCost`, and period reset dates are ignored.
- Active subscription period dates populate `resetsAt` (`currentPeriodEnd`) and `windowSeconds` (`currentPeriodEnd - currentPeriodStart`) on the `Credits` quota.
- Unknown plan without `summary.totalCost` (or inactive subscription): no cap, so a balance-only card (money only, no percentage, as data), emitted **only** when there are no window quotas, so the card is never empty but a fake percentage never sits next to real ones.
