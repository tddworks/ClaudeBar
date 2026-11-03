# Cursor: design

Contributor notes for Cursor. User-facing setup is in [README.md](README.md).

## As data

Cursor is `Modules/Providers/Resources/Providers/cursor.json` and `cursor-usage.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it.

- **Key — default login.** `CredentialLookup.sqlite` reads `cursorAuth/accessToken` from the app's `state.vscdb`. The database is opened read-only, and a query that would change it is refused. The lookup's `hint` ("Sign in again in Cursor settings, then refresh.") is what the Accounts card says when the key is gone. `requiresFiles` makes a missing database *Couldn't read your key* and not *Configured*. Newer Cursor (3.27.22 reported, October 2026) seals the cell when `cursor.storage.authTokenEncryptionAtRest` is on (`cursor-safe-storage:v1:` and base64 of Electron's safeStorage); the lookup's `sealed` opens it with Cursor's own key, the Keychain item `Cursor Safe Storage` on the Mac and the key in `Cursor/Local State` on Windows, and a token an older Cursor wrote in the clear is used as it is ([#655](https://github.com/tddworks/ClaudeBar/issues/655)).
- **Key — added account.** The lookup is the app's database, then a saved `accessToken` (account scope, in the vault). The database and `requiresFiles` are at fixed paths, so they are this Mac's: an added account reaches only its own token ([what an account's sign-in reaches](../../features/providers/multi-account/design.md#what-an-accounts-sign-in-reaches), #577).
- **User id.** The session cookie is `WorkosCursorSessionToken={{token#jwt.sub}}::{{token}}`: the id is the token's own `sub` claim, read (not verified) when the request is filled, whichever lookup found the key. A token with no `sub` sends no cookie, and Cursor's 401 says so.
- **Errors.** `http.401` carries the re-authenticate hint, `http.403` is *Authentication required*, and a 429 is a rate limit (the old probe said "HTTP error: 429"). Only 200 is an answer (`acceptedStatuses`).
- **Left law.** An unlimited plan gives the plan and no quota, where the old probe showed a 100% "Monthly" card.

## Source

Cursor has no CLI that reports usage, so the probe borrows the Cursor app's session:

1. **Token.** The read-only SQLite connection queries `{{platform.appData}}/Cursor/User/globalStorage/state.vscdb` with `SELECT value AS token FROM ItemTable WHERE key = 'cursorAuth/accessToken'`. Empty output → signed out → authentication required.
2. **User id.** The access token is a JWT; its `sub` claim (base64url payload, padded before decoding) is the user id.
3. **Request.** `GET https://cursor.com/api/usage-summary` with `Cookie: WorkosCursorSessionToken={sub}::{accessToken}`.

HTTP 401 → session expired (the token in the database is stale); 403 → authentication required.

The probe is available only when `state.vscdb` exists, so a computer without Cursor never shows a missing-file error. The same `{{platform.appData}}` prefix is used by `requiresFiles` and the credential lookup: macOS keeps `~/Library/Application Support`, Windows uses nonempty `APPDATA` or `~/AppData/Roaming`. Windows SQLite and script mapping connections remain unavailable until the quotas phase; portable paths do not enable them.

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

- `billingCycleEnd` is the reset time for Monthly, On-Demand, Team and Team Pool (ISO 8601, with or without fractional seconds).
- **`plan` → "Monthly" card.** Capacity is `max(limit, breakdown.total)`. `used`/`limit` describe only the included base: with bonus credits the base reads maxed (`used == limit`) while `breakdown.total` is included + bonus, and Enterprise reports `limit: 0` with everything in the breakdown. Percent comes from `totalPercentUsed` when present (it matches Cursor's "You've used X%" message) and from `used/limit` otherwise ([#230](https://github.com/tddworks/ClaudeBar/pull/230), [#136](https://github.com/tddworks/ClaudeBar/issues/136)). Request-count `resetText` stays on this card only.
- **`plan.autoPercentUsed` → "Auto" card** and **`plan.apiPercentUsed` → "API" card**, only when the field is a finite non-negative number (JSON ints such as `0` count). Remaining is `max(0, 100 - percentUsed)`. The three percentages are shown as the API reports them; ClaudeBar does not derive one from the others. When both `billingCycleStart` and `billingCycleEnd` parse and end is after start, these cards get that length as `windowDuration` and the same reset date as Monthly. If start is missing or the dates are unusable, the cards still appear but without `resetsAt`, so pace does not fall back to the generic 7-day `.timeLimit` window. Negative, null, boolean and other non-numeric values omit the card.
- **`onDemand` → "On-Demand" card**, only when `enabled` and `limit > 0`.
- **`teamUsage.onDemand` → "Team" card**, only when `limitType == "team"` and it's enabled with a limit (Enterprise, #136).
- **`individualUsage.overall` → "Monthly" card in dollars**, when there is no plan card. Some team seats (Enterprise) get no `plan` block: their spend and its cap are `overall`, in cents. The card is the money left of the cap. Only when `enabled` and `limit > 0` ([#614](https://github.com/tddworks/ClaudeBar/issues/614)).
- **`teamUsage.pooled` → "Team Pool" card in dollars**: the usage the whole team shares (Enterprise), cents left of the pool's limit, same rule.
- **`isUnlimited: true`** with no other card gives the plan and no quota (the Left law above).
- `membershipType` becomes the tier badge (`pro`, `business`, `free`, `ultra`, `enterprise`; anything else is upper-cased).
- Numbers can arrive as ints or doubles; both are accepted.

A team seat without a `plan`, as CodexBar recorded it from a live Enterprise account ([steipete/CodexBar#813](https://github.com/steipete/CodexBar/pull/813)); ClaudeBar's test uses it as it is:

```json
{
  "membershipType": "enterprise",
  "limitType": "team",
  "isUnlimited": false,
  "individualUsage": {
    "overall": { "enabled": true, "used": 7384, "limit": 10000, "remaining": 2616 }
  },
  "teamUsage": {
    "onDemand": { "enabled": true, "used": 0, "limit": null, "remaining": null },
    "pooled":   { "enabled": true, "used": 12725135, "limit": 28122000, "remaining": 15396865 }
  }
}
```

## Known limits

- **Units.** The plan card's text says "requests" (`2767/9770 requests`), but the values look like US cents: a Pro plan reports `limit: 2000` ($20 included) and an Ultra plan `limit: 40000`. Unconfirmed; don't build dollar maths on it without checking against the dashboard. `overall` and `pooled` are cents: CodexBar and CursorMeter both matched them to the dashboard's dollars.
- **A seat's cap that isn't in the response.** CursorMeter reports that token-based Enterprise seats send `overall` with `limit: null` and read the cap from `POST /api/dashboard/get-hard-limit` with the team's id ([API reference](https://github.com/WoojinAhn/CursorMeter/blob/main/docs/API_REFERENCE.md)). ClaudeBar makes one request, so such a seat still reads "No usage data". No response of this kind has been shared with ClaudeBar yet.
- The endpoint and cookie are private to cursor.com and can change without notice. The first fix after launch (`822ebc4`) was exactly that: the real response nests usage under `individualUsage.plan` / `individualUsage.onDemand`, not the top-level `planUsage` / `onDemandUsage` first assumed.
