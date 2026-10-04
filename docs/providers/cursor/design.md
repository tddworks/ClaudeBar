# Cursor: design

Contributor notes for Cursor. User-facing setup is in [README.md](README.md).

## As data

Cursor is `Modules/Providers/Resources/Providers/cursor.json` and `cursor-usage.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it.

- **Key — default login.** `CredentialLookup.sqlite` reads `cursorAuth/accessToken` from the app's `state.vscdb`. The database is opened read-only, and a query that would change it is refused. The lookup's `hint` ("Sign in again in Cursor settings, then refresh.") is what the Accounts card says when the key is gone. `requiresFiles` makes a missing database *Couldn't read your key* and not *Configured*.
- **Key — added account.** Its patch drops the database and `requiresFiles`, and reads its own saved `accessToken` (account scope, in the vault).
- **User id.** The session cookie is `WorkosCursorSessionToken={{token#jwt.sub}}::{{token}}`: the id is the token's own `sub` claim, read (not verified) when the request is filled, whichever lookup found the key. A token with no `sub` sends no cookie, and Cursor's 401 says so.
- **Errors.** `http.401` carries the re-authenticate hint, `http.403` is *Authentication required*, and a 429 is a rate limit (the old probe said "HTTP error: 429"). Only 200 is an answer (`acceptedStatuses`).
- **Left law.** An unlimited plan gives the plan and no quota, where the old probe showed a 100% "Monthly" card.

## Source

Cursor has no CLI that reports usage, so the probe borrows the Cursor app's session:

1. **Token.** `/usr/bin/sqlite3 ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"`. Empty output → signed out → authentication required.
2. **User id.** The access token is a JWT; its `sub` claim (base64url payload, padded before decoding) is the user id.
3. **Request.** `GET https://cursor.com/api/usage-summary` with `Cookie: WorkosCursorSessionToken={sub}::{accessToken}`.

HTTP 401 → session expired (the token in the database is stale); 403 → authentication required.

The probe is available only when `state.vscdb` exists, so a Mac without Cursor never shows an error.

## Response fields that matter

```json
{
  "membershipType": "pro",
  "limitType": "team",
  "isUnlimited": false,
  "billingCycleStart": "2026-03-01T00:00:00.000Z",
  "billingCycleEnd": "2026-04-01T00:00:00.000Z",
  "individualUsage": {
    "plan": {
      "enabled": true, "used": 2000, "limit": 2000, "remaining": 0,
      "breakdown": { "included": 2000, "bonus": 7770, "total": 9770 },
      "autoPercentUsed": 23.05,
      "apiPercentUsed": 63.44,
      "totalPercentUsed": 28.32
    },
    "onDemand": { "enabled": false, "used": 0, "limit": null }
  },
  "teamUsage": { "onDemand": { "enabled": true, "used": 0, "limit": 10000 } }
}
```

- `billingCycleEnd` is the reset time for Monthly, On-Demand and Team (ISO 8601, with or without fractional seconds).
- **`plan` → "Monthly" card.** Capacity is `max(limit, breakdown.total)`. `used`/`limit` describe only the included base: with bonus credits the base reads maxed (`used == limit`) while `breakdown.total` is included + bonus, and Enterprise reports `limit: 0` with everything in the breakdown. Percent comes from `totalPercentUsed` when present (it matches Cursor's "You've used X%" message) and from `used/limit` otherwise ([#230](https://github.com/tddworks/ClaudeBar/pull/230), [#136](https://github.com/tddworks/ClaudeBar/issues/136)). Request-count `resetText` stays on this card only.
- **`plan.autoPercentUsed` → "Auto" card** and **`plan.apiPercentUsed` → "API" card**, only when the field is a finite non-negative number (JSON ints such as `0` count). Remaining is `max(0, 100 - percentUsed)`. The three percentages are shown as the API reports them; ClaudeBar does not derive one from the others. When both `billingCycleStart` and `billingCycleEnd` parse and end is after start, these cards get that length as `windowDuration` and the same reset date as Monthly. If start is missing or the dates are unusable, the cards still appear but without `resetsAt`, so pace does not fall back to the generic 7-day `.timeLimit` window. Negative, null, boolean and other non-numeric values omit the card.
- **`onDemand` → "On-Demand" card**, only when `enabled` and `limit > 0`.
- **`teamUsage.onDemand` → "Team" card**, only when `limitType == "team"` and it's enabled with a limit (Enterprise, #136).
- **`isUnlimited: true`** adds a 100% "Monthly" card labelled "Unlimited".
- `membershipType` becomes the tier badge (`pro`, `business`, `free`, `ultra`, `enterprise`; anything else is upper-cased).
- Numbers can arrive as ints or doubles; both are accepted.

## Known limits

- **Units.** The card text says "requests" (`2767/9770 requests`), but the values look like US cents: a Pro plan reports `limit: 2000` ($20 included) and an Ultra plan `limit: 40000`. Unconfirmed; don't build dollar maths on it without checking against the dashboard.
- **Unlimited plus plan.** If a response had both `isUnlimited: true` and an enabled plan, two "Monthly" cards would be produced. No such response has been seen.
- The endpoint and cookie are private to cursor.com and can change without notice. The first fix after launch (`822ebc4`) was exactly that: the real response nests usage under `individualUsage.plan` / `individualUsage.onDemand`, not the top-level `planUsage` / `onDemandUsage` first assumed.
