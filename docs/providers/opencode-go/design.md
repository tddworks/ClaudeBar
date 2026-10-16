# OpenCode Go: design

Contributor research for the OpenCode Go provider (`opencode-go`). User-facing setup is in [README.md](README.md).

## As data

OpenCode Go is `Modules/Providers/Resources/Providers/opencode-go.json`, `opencode-api.js` and `opencode-local.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it.

- **`api`** — `http` with the key from `OPENCODE_API_KEY`, then `auth.json`'s `opencode-go`, then its `opencode` entry (`${XDG_DATA_HOME:-~/.local/share}`). `errors` keeps 401 → *session expired* with the `opencode auth login` hint and 403 → *subscription required*; a 429 is a rate limit. `fallbackOn.authenticationRequired` hands a missing key — never a rejected one — to `local`.
- **`local`** — the engine's `sqlite` fetch running **one fixed read-only query** against opencode's own database file (`${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db`, shown word for word on Import), read straight, never through the CLI. SQLite works out every window itself from `'now'`: the 5-hour window and its oldest spend, the UTC Monday-to-Monday week, and the month anchored on the first opencode-go message. The anchor's day is clamped to each month's last day: a 31st anchor runs Apr 30 → May 31. The old probe's `Calendar` rolled such a day over instead, so anchors on the 29th–31st can differ by a day or two from before. No planner script computes arguments; the query is tested against a real SQLite database (`OpenCodeDefinitionTests`).
- **`local1`** — the same fetch with the **same-shaped query against opencode v1's `message` table**, reached only as `local`'s `fallback`. OpenCode v2 rewrote its store: v1 keeps messages in `message` (`data.role = 'assistant'`, provider at `data.providerID`); v2 keeps them in `session_message` (`type = 'assistant'`, provider at `data.model.providerID`, tokens gain a `reasoning` count) and removed the `opencode db` subcommand (#566). One SQL statement cannot span both schemas — SQLite resolves table names when it prepares — so the definition carries one query per layout and the engine's fallback chain picks: `local` queries `session_message` and also selects `is_v2`, a guard that is `1` only when the database has v2's `session_v2` table; `opencode-local.js` answers `parseFailed` when it reads `0`, which hands a v1 database to `local1` (whose row carries no `is_v2`, so the same script reads it as before). A database with neither table (or no file at all) fails both and surfaces as a probe error. Both layouts emit the same column names, so one mapping reads either. Both sources are patched away for added accounts (`"local": null`, `"local1": null`).
- **Money** — each local cap is `left: { money, of }` ($12, $30, $60) to the cent. With no message yet there is no billing month: the monthly quota states no window rather than a guessed 30 days.
- **Accounts** — an added account has its own saved key (`apiKey`, account scope) and never falls back to this Mac's database (`"local": null`, `"local1": null`).
- **Usage history** — `usageHistory` runs **one fixed read-only query per layout** of the same database file through DataSources' sqlite log reader: `records` reads v2's `session_message`, `also` reads v1's `message`, and the two answers are read as one log — every assistant message the database holds, **whatever provider it drove** — Zen (`providerID = 'opencode'`), OpenCode Go, a custom endpoint — as one total, the leaderboard's and the cards' unit being the tool, not the plan. A layout the database doesn't have (v2 fresh has no `message`; old v1 has no assistant rows in `session_message`) contributes nothing, so an upgraded install's history spans its v1 past and its v2 present. The SQL emits each row's `role` (the shape's `where` names it, as the law asks), `id`, time in **seconds** (`ms / 1000` — the reader reads epoch seconds, not milliseconds), the four token counts, and the log's own `cost`, so `knowsCost` holds with no price file. A `where` on the `time.created` JSON type keeps out rows without a time. The queries carry **no window of their own**: one once cut at `now − 30 days`, which knows neither the range asked for nor local midnight, so a closed day it left out was read as empty and kept empty by the ledger for good. `days(in:)` cuts to the range instead, exactly as it does for a file log. An added login gets **no** usage history (`accounts.patch` says nothing): the database belongs to the Mac, and two logins must never count it twice. Tested against a real SQLite database (`OpenCodeUsageHistoryTests`).

## Sources and order

1. **Usage API** when an API key resolves. `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <key>`. Added upstream in anomalyco/opencode#16513; ClaudeBar switched to it in #249 (2026-08).
2. **Local database** only when *no* key resolves: opencode's own SQLite store read directly, v2's `session_message` layout first, v1's `message` layout as `local`'s fallback. Until #566 this ran `opencode db "<sql>" --format json` — a subcommand v2 removed — which is why the read now goes through the engine's `sqlite` fetch instead of the CLI.

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

Rows: assistant messages whose JSON `data` names the Go provider and a numeric `cost` — `providerID = 'opencode-go'` at the top of v1's `message.data`, `model.providerID = 'opencode-go'` inside v2's `session_message.data`. Time is `data.time.created` (epoch milliseconds in both), falling back to the row's `time_created` column. Guards: `json_valid(data)` and `json_type(data, '$.cost') IN ('integer','real')`, because the tables hold malformed or cost-less rows.

Limits are hard-coded plan dollars: **$12 / 5 h, $30 / week, $60 / month**. Over the limit clamps to 0%.

Window semantics, tuned against opencode.ai/account (2026-05) — identical in both layouts:

| Window | Rule | Reset shown |
|---|---|---|
| 5-hour | Rolling, ending now | Oldest message in the window + 5 h (now + 5 h if empty) |
| Weekly | Fixed, UTC Monday 00:00 → next Monday | Next UTC Monday |
| Monthly | Anchored to the user's **first ever** opencode-go message: same day-of-month and time-of-day each cycle; a day that doesn't exist (31st) clamps to the month's last day | Anchor + 1 month |

One query per layout computes 5-hour cost, weekly cost, oldest-in-5h and the anchor (`MIN(t)`); the monthly sum only runs when an anchor exists.

### The database file

One file, whatever the CLI version: `${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db`, opened read-only. opencode writes intermediate installs (`dev`, `beta`, `next` channels) to a channel-suffixed name and honours `$OPENCODE_DB`; ClaudeBar reads the stable name and knows nothing of those. A missing file or a missing table surfaces as a probe error, not an empty card.

## Dead ends

- **Local Sunday weekly window and calendar month.** The first version used them; weekly reset countdowns were ~1 d 5 h off and monthly ~12 d off the dashboard. Replaced by UTC Monday and the first-message anchor (commit ba832ec).
- **Counting every opencode message.** Only `providerID = 'opencode-go'` spend counts toward Go quota (fcb0af2).
- **`opencode db path` in `isAvailable()`.** Spawned an extra subprocess per refresh; availability is now just "`opencode` is on the PATH", and a missing database surfaces as a probe error.
- **One query spanning both layouts.** A `UNION` of `message` and `session_message` fails to prepare wherever either table is missing — SQLite resolves names at prepare time, and v2-fresh has no `message`. Two queries with the fallback chain instead (#566).
- **`opencode db` as the reader.** The subcommand survived every v1 release and died with v2.0; reading the file through the engine's `sqlite` fetch survives both and spawns no subprocess (#566).
