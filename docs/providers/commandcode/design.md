# Command Code: probe design

Contributor research for the Command Code provider (`commandcode`). User-facing setup is in [README.md](README.md). Added in ba390fc (2026-09).

## Sources

Two calls, mirroring the `cmd` CLI's `/usage` command, both with `Authorization: Bearer <API key>`:

1. `GET https://api.commandcode.ai/alpha/whoami?limits=1` → `org.id` and the account name (`user.userName`, else `user.name`).
2. `GET https://api.commandcode.ai/alpha/billing/credits?orgId=<org.id>` (no `orgId` when whoami returned none) → the quota payload.

Any 2xx must be a JSON object or the call is a parse failure. 401/403 → `sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")`. There's no token refresh: the key is long-lived.

## API key lookup

1. `COMMAND_CODE_API_KEY`
2. `COMMANDCODE_API_KEY`
3. `apiKey` in `~/.commandcode/auth.json`, a flat `{ "apiKey": "user_..." }` written by `cmd login`

Environment variables come from the app's process environment.

## Credits response

```json
{
  "credits": {
    "monthlyCredits": 8.5, "purchasedCredits": 0, "freeCredits": 0,
    "planId": "individual-go"
  },
  "windowLimits": {
    "fiveHour": { "used": 10, "cap": 40,  "resetAt": 1770000000000 },
    "weekly":   { "used": 50, "cap": 200, "resetAt": 1770500000000 }
  }
}
```

- Some deployments wrap the payload in `data` (the CLI reads `a.data`); both shapes are read, for whoami too.
- `windowLimits.fiveHour` → session (5 h), `weekly` → weekly (7 d). Remaining = `(cap - used) / cap`; a window with no positive `cap` is skipped.
- `resetAt` arrives as epoch **milliseconds**, epoch **seconds** or an ISO 8601 string depending on the window. Numbers above 1e12 are treated as milliseconds.
- Numbers may be JSON numbers or numeric strings.

## Credits meter

`monthlyCredits` is treated as the **remaining** monthly allowance, not the allowance itself, so the cap comes from the plan id: a hard-coded map of plan-id prefix → monthly dollars (`planTotals` in the probe; e.g. `individual-go` $10, `individual-ultra` $300). It has to be updated by hand when Command Code changes its plans.

- The plan id is lowercased, `_` → `-`, and matched by prefix, **longest key first**, so `individual-pro-v1` doesn't match `individual-pro`.
- Remaining = monthly + purchased + free. Cap = max(plan allowance, monthly) + purchased + free; the `max` guards against a balance above the known allowance.
- Unknown plan: no cap, so a balance-only card at a fixed 100%, emitted **only** when there are no window quotas, so the card is never empty but a fake percentage never sits next to real ones.
