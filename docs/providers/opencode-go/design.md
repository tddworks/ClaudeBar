# OpenCode Go: design

Contributor research for the OpenCode Go provider (`opencode-go`). User-facing setup is in [README.md](README.md).

## As data

OpenCode Go is `Modules/Providers/Resources/Providers/opencode-go.json`, `opencode-api.js` and `opencode-local.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it.

- **`api`** — `http` with the key from `OPENCODE_API_KEY`, then `auth.json`'s `opencode-go`, then its `opencode` entry (`${XDG_DATA_HOME:-~/.local/share}`). `errors` keeps 401 → *session expired* with the `opencode auth login` hint and 403 → *subscription required*; a 429 is a rate limit. `fallbackOn.authenticationRequired` hands a missing key — never a rejected one — to `local`.
- **`local`** — a `command` running **one fixed read-only query**: `opencode db "<SQL>" --format json`, shown word for word on Import. SQLite works out every window itself from `'now'`: the 5-hour window and its oldest spend, the UTC Monday-to-Monday week, and the month anchored on the first opencode-go message. The anchor's day is clamped to each month's last day: a 31st anchor runs Apr 30 → May 31. The old probe's `Calendar` rolled such a day over instead, so anchors on the 29th–31st can differ by a day or two from before. No planner script computes arguments; the query is tested against a real SQLite database (`OpenCodeDefinitionTests`).
- **Money** — each local cap is `left: { money, of }` ($12, $30, $60) to the cent. With no message yet there is no billing month: the monthly quota states no window rather than a guessed 30 days.
- **Accounts** — an added account has its own saved key (`apiKey`, account scope) and never falls back to this Mac's database (`"local": null`).

## Sources and order

1. **Usage API** when an API key resolves. `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <key>`. Added upstream in anomalyco/opencode#16513; ClaudeBar switched to it in #249 (2026-08).
2. **Local database** only when *no* key resolves. `opencode db "<sql>" --format json` against opencode's own SQLite store.

A key that resolves but is rejected does **not** fall back to the database: 401 becomes `sessionExpired` (hint: `opencode auth login` → OpenCode Zen), 403 becomes `subscriptionRequired` (key has no Go subscription). Falling back there would show a silent estimate instead of telling the user their key is bad.

### Why the API replaced the database

The database only sees this machine's messages and has to guess the server's cost accounting, so its numbers drifted from the opencode.ai dashboard. The endpoint returns the same figures the dashboard shows.

## API key lookup

1. `OPENCODE_API_KEY` (from the app's process environment, so a shell-only export is invisible to a Finder-launched app)
2. `auth.json` entry `opencode-go`, then `opencode` (the shared Zen entry). Each entry is `{ "type": "api", "key": "sk-..." }`; only `key` is read.

`auth.json` lives at `$XDG_DATA_HOME/opencode/auth.json`, default `~/.local/share/opencode/auth.json`. It also holds other providers' OAuth entries (`anthropic`, …); they are ignored.

## Usage API response

```json
{ "usage": {
    "rolling": { "status": "ok", "percent": 17, "resetsAt": "2026-08-24T12:00:00.000Z" },
    "weekly":  { "status": "ok", "percent": 40, "resetsAt": "..." },
    "monthly": { "status": "ok", "percent": 55, "resetsAt": "..." } } }
```

- `percent` is **used**, not remaining. Remaining = `100 - percent`, clamped to 0–100.
- `status` is `"ok"` or `"rate-limited"`; rate-limited forces 0% remaining regardless of `percent`.
- `percent` may arrive as a number or a numeric string; both are accepted.
- `resetsAt` is ISO 8601, with or without fractional seconds.
- Mapping: `rolling` → session (5 h window), `weekly` → weekly (7 d), `monthly` → `Monthly` (no fixed window length). A missing window is skipped; no windows at all is a parse error.

## Local database fallback

Rows: assistant messages whose JSON `data` has `providerID = 'opencode-go'` and a numeric `cost`. Time is `data.time.created`, falling back to the `time_created` column. Guards: `json_valid(data)` and `json_type(data, '$.cost') IN ('integer','real')`, because the table holds malformed or cost-less rows.

Limits are hard-coded plan dollars: **$12 / 5 h, $30 / week, $60 / month**. Over the limit clamps to 0%.

Window semantics, tuned against opencode.ai/account (2026-05):

| Window | Rule | Reset shown |
|---|---|---|
| 5-hour | Rolling, ending now | Oldest message in the window + 5 h (now + 5 h if empty) |
| Weekly | Fixed, UTC Monday 00:00 → next Monday | Next UTC Monday |
| Monthly | Anchored to the user's **first ever** opencode-go message: same day-of-month and time-of-day each cycle; a day that doesn't exist (31st) clamps to the month's last day | Anchor + 1 month |

Two queries: one computes 5-hour cost, weekly cost, oldest-in-5h and the anchor (`MIN(t)`); the monthly sum only runs when an anchor exists.

## Dead ends

- **Local Sunday weekly window and calendar month.** The first version used them; weekly reset countdowns were ~1 d 5 h off and monthly ~12 d off the dashboard. Replaced by UTC Monday and the first-message anchor (commit ba832ec).
- **Counting every opencode message.** Only `providerID = 'opencode-go'` spend counts toward Go quota (fcb0af2).
- **`opencode db path` in `isAvailable()`.** Spawned an extra subprocess per refresh; availability is now just "`opencode` is on the PATH", and a missing database surfaces as a probe error.
