---
description: Contributor design for the Leaderboard. Join with a username, share daily token totals from chosen providers, see your rank. Covers the model, its laws, the signed API, the server's storage and the build order.
---

# Leaderboard: design

**Status:** BUILT on `feat/leaderboard`, not yet deployed: the app side, the Worker and the board page exist and are tested; the Worker has no production database or URL until a maintainer deploys it ([Server/leaderboard/README.md](../../../Server/leaderboard/README.md)). User guide: [README.md](README.md). The screens are drawn in [design-concept/leaderboard/index.html](../../../design-concept/leaderboard/index.html). This document is the contract the build follows; where code later disagrees, the code is behind until this document says otherwise.

This document owns **joining the board, what a member shares, how a member's uploads are trusted, and how standings are ranked**. Its neighbours own the rest:

| For | Read |
|---|---|
| How a day's tokens are read from a tool's logs, and deduplicated | [daily-usage/design.md](../daily-usage/design.md) |
| `UsageHistory`, the login that owns it, and the 30-day ledger | [CANONICAL_MODEL.md](../../architecture/CANONICAL_MODEL.md) |
| Where settings persist | [docs/settings.md](../../settings.md) |
| The other destination ClaudeBar sends its own state to, and its Keychain fallback | [notify/design.md](../notify/design.md) |

---

## What the product already says

The design concept is the only surface so far, and its words are where the names below come from.

```
  "Join the board"                      ← joining is the act; the board is the place
  "Username · Shown publicly"           ← the one public identity, chosen, not derived
  "Share tokens from  ☑ Claude ☑ Codex" ← sharing is per provider, opt-in
  "no token logs"                       ← a provider without usage history cannot be shared
  "Exactly what gets uploaded"          ← daily totals, nothing else
  "#7 · 93M tokens · 7 days · ▲ 2"      ← a rank is relative to a period and a provider
  "Today | 7 days | 30 days"            ← the periods, a closed set
  "Leave and delete my data"            ← leaving is deletion, not hiding
  "Show me on the web board"            ← visibility is separate from membership
```

Two findings fall out of these. A rank is never a property of a member alone; it is a member's place in one **board view** (period × provider). And "leave" and "hide" are different acts: hiding keeps your rows and your own rank, leaving destroys both.

## The one sentence

**A member shares the daily token totals of the providers they chose, signed by a key only their Mac holds, and the board ranks members by those totals over a period.**

```
   this Mac                                   the server (Worker + D1)
 ┌──────────────────────────────┐   signed   ┌────────────────────────────┐
 │ Membership                   │ ─────────▶ │ members   (username, key)  │
 │  username, sharing, key      │  PUT /usage│ daily_tokens (one row per  │
 │ UsageHistory per login ──▶   │            │   member·provider·day)     │
 │   DailyTokens per provider   │ ◀───────── │ standings  (ranked view)   │
 └──────────────────────────────┘ GET /board └────────────────────────────┘
```

---

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Board** | The ranking, as one public page and one popover tab | a provider's *dashboard* link |
| **Member** | Someone who joined: a username on the server with one public key | a provider *account* (a login); a member may have several logins per provider |
| **Membership** | This Mac's side of being a member: the username, the private key, what is shared, whether visible | the server's member row, which never holds the private key |
| **Username** | The public name, chosen at join, unique ignoring case | an account email, which is never sent |
| **Daily tokens** | One provider's token counts for one local calendar day on this Mac: input, output, cache write, cache read, and *unsplit* — tokens a log keeps only as a total (Mistral) | `DailyUsageStat`, which also carries cost, sessions and working time that are never shared |
| **Sharing** | The providers a member chose to upload | a provider being *enabled* in ClaudeBar |
| **Upload** | One signed `PUT /usage` carrying days of daily tokens | a *refresh*, which fetches quotas |
| **Board view** | A period and a provider filter: `7 days · Claude` | a period alone |
| **Period** | `today`, `7d` or `30d`. Closed | an arbitrary date range |
| **Standing** | One member's place in one board view: rank, username, totals, provider mix | the member |
| **Visible** | Whether the member appears on the public board. A hidden member is still ranked for themselves | membership |
| **Signing key** | The Ed25519 key pair made on join. Private half on this Mac, public half on the server | an API token; there is no shared secret anywhere |

"Daily tokens" is chosen over the user's "token usage" because *usage* already means quota usage everywhere else in ClaudeBar. Do not rename it back.

## 2 · The aggregate, from the root down

Two aggregates, one on each side of the wire. Neither reaches into the other; they meet only in the API.

```
LeaderboardMembership                     this Mac's membership (aggregate root, app)
 ├─ username : Username?                  nil = not joined; the only "joined" flag
 ├─ sharing : Set<ProviderID>             ONLY PROVIDERS WITH USAGE HISTORY
 ├─ isVisible : Bool                      hidden members still see their own standing
 ├─ key : SigningKey                      PRIVATE HALF NEVER LEAVES THE MAC
 └─ lastUpload : Date?                    where the next upload resumes

Board                                     the server's ranking (aggregate root, Worker)
 ├─ members : Member                      username, public key, visible, joined at
 ├─ members.today                        THE MEMBER'S OWN DATE: THEIR PERIODS END ON IT
 ├─ members.suspended                    SET ONLY BY A MAINTAINER, NEVER THROUGH THE API
 └─ dailyTokens : DailyTokens             ONE ROW PER MEMBER · PROVIDER · DAY
     └─ standings(view) → [Standing]      RANKED BY TOTAL TOKENS, TIES BY USERNAME
```

There is no `Leaderboard` type on the app side that holds standings. The app does not own the ranking, so it only asks the server for a board view and draws what comes back; caching it would give the app a second opinion about rank.

### `LeaderboardMembership`: this Mac's membership

> **Pointable as:** a membership card. A name on the front, a key in your pocket, and a list of what you agreed to share.

| | |
|---|---|
| **Owns: only shared providers leave the Mac** | `dailyTokens(from:)` drops every provider not in `sharing` before anything is built |
| **Owns: only shareable providers can be shared** | `share(_:)` refuses a provider with no usage history; the ability is absent, not ignored |
| **Tell it** | `join(as:sharing:)` · `share(_:)` · `stopSharing(_:)` · `setVisible(_:)` · `rename(to:)` · `leave()` |
| **It answers** | `isJoined` · `sharing` · `myStanding(in:)` |
| **Never** | holds a ranking · sends a provider it was not told to share · forgets its key before the server confirmed the leave |

### `DailyTokens`: one provider's day

> **Pointable as:** a line on a tally sheet: provider, date, four counts.

| | |
|---|---|
| **Owns: totals only** | made from a `DailyUsageStat` by keeping four counts; cost, sessions, working time, model names and paths cannot be expressed in it |
| **It answers** | `total` (the four counts summed) |
| **Never** | carries anything that names a project, a file, a prompt or an account |

### `Username`

> **Pointable as:** the name on the board.

3 to 20 characters of `A–Z a–z 0–9 - _`, unique ignoring case. The value type exists so an invalid name cannot be held at all; uniqueness is the server's to answer.

## 3 · The tells

```swift
// Join: the membership makes its key, the server answers whether the name is free.
try await membership.join(as: Username("tokenwhale"), sharing: [.claude, .codex])

// Hourly, and once right after joining (driver, like NotifyPublishDriver).
await uploader.uploadDue()                       // asks the membership for its days; never filters itself

// Settings
membership.share(.mistral)                       // throws if Mistral has no usage history on this Mac
membership.setVisible(false)
try await membership.leave()                     // server deletes first, then the key is forgotten

// Popover
let standings = try await board.standings(in: BoardView(period: .sevenDays, provider: nil))
let mine = try await membership.myStanding(in: view)
```

The ask this design exists to prevent:

```swift
// ASK: the uploader decides what leaves the Mac. Every caller repeats the rule.
for p in providers where settings.shared.contains(p.id) && p.usageHistory != nil { … }

// TELL
let days = membership.dailyTokens(from: usageHistories, in: range)
```

## 4 · Invariants: each law, one owner

| Law, in the user's terms | Owner |
|---|---|
| Only providers you ticked are uploaded | `LeaderboardMembership.dailyTokens(from:in:)` |
| A provider without token logs can't be ticked | `LeaderboardMembership.share(_:)` |
| Nothing but four token counts per provider per day leaves the Mac | `DailyTokens` (its shape) |
| A provider's day is the sum of all its logins on this Mac | `LeaderboardMembership.dailyTokens(from:in:)` |
| Your private key never leaves your Mac and is never logged | `SigningKeyStore` (Keychain, with the UserDefaults fallback Notify! uses for ad-hoc builds) |
| Uploading a day again replaces it; it never adds | Worker, `PUT /usage` (`PRIMARY KEY (member, provider, day)` upsert) |
| A missed hour, or a Mac asleep for days, heals on the next upload | `LeaderboardUploader`: uploads from the day of `lastUpload` to today, at most 30 days, and on join the last 30 |
| Every write and every private read is signed by the member's key | Worker, signature check before any handler |
| Who you are comes from the verified signature, never from a parameter | Worker, signature check |
| A signed request is accepted once, and only within 5 minutes of its timestamp | Worker, nonce table |
| A username is unique ignoring case | Worker, `POST /join` (`UNIQUE` on `lower(username)`) |
| A username is 3–20 of `A–Z a–z 0–9 - _` | **Two owners, deliberately:** `Username` for instant feedback, the Worker as authority. The rule is pinned by one shared test vector file both suites read, so they cannot drift silently |
| No future days, nothing older than 30 days, no day above the plausibility cap | Worker, `PUT /usage` |
| Standings rank by total tokens (the five counts summed); ties by username | Worker, `board.ts` |
| A member's period ends on their own date, the one their Mac sent with its last upload, while it is within a day of UTC's | Worker, `board.ts` |
| A suspended member is off the public board whatever they set | Worker, `board.ts` |
| A hidden member is absent from the public board and still sees their own standing | Worker, `GET /board` vs `GET /me` |
| Leaving deletes the member and every row, on the server | Worker, `DELETE /me`; the app forgets the key only after a 2xx |

## 5 · The API

Host: a Cloudflare Worker. Storage: Cloudflare D1. The board page is static on GitHub Pages and reads `GET /board`. The app holds no secret: only the Worker can reach D1, through its database binding.

| Route | Auth | Does |
|---|---|---|
| `POST /join` `{username, publicKey}` | none, rate-limited per IP | creates the member, or `409` if the name is taken |
| `PUT /usage` `{today, days: [DailyTokens]}` | signed | upserts each day; `today` is the Mac's date, refused when more than a day from UTC's |
| `GET /me` | signed | the member, their standing in a view, every row they uploaded |
| `GET /me/export` | signed | the same, as a downloadable JSON file |
| `PATCH /me` `{username?, visible?}` | signed | rename, hide or show |
| `DELETE /me` | signed | deletes the member and every row |
| `GET /board?period=7d&provider=claude` | none | standings of visible members, cached a few minutes |

**Signing.** On join the app makes a `Curve25519.Signing.PrivateKey` (CryptoKit) and sends its public half. Every signed request carries:

```
X-Member:    <username>
X-Timestamp: <unix seconds>
X-Nonce:     <16 random bytes, base64url>
X-Signature: base64url( sign( METHOD \n PATH?QUERY \n TIMESTAMP \n NONCE \n hex(SHA256(body bytes)) ) )
```

The Worker verifies with WebCrypto's Ed25519 against the stored public key, over **the exact bytes received**, never re-serialised JSON. The canonical string is pinned by test vectors that the Swift and Worker suites both run.

**Storage.**

The schema is [`migrations/0001_init.sql`](../../../Server/leaderboard/migrations/0001_init.sql): `members` (username unique ignoring case, public key, `visible`, `suspended`, `today`), `daily_tokens` (one row per member, provider and day, five counts), and `nonces`, swept hourly by the Worker's cron.

Every query is a prepared statement. A standing is one `SUM(input + output + cache_write + cache_read + unsplit) … GROUP BY member` over the view's days.

CryptoKit's Ed25519 signatures are randomised, so the shared vectors are **verified** on both sides, never compared byte for byte.

## 6 · Privacy

The second destination after Notify! that sends ClaudeBar's own state outward, so the same rules apply, stated plainly:

- **What leaves the Mac:** the username, and per shared provider per day four token counts. No cost, no model names, no projects, no paths, no prompts, no account email.
- **Where it goes:** a Cloudflare Worker run by tddworks, and from there to a public page if visible.
- **Off by default.** Nothing is sent until the user joins, and only for providers they tick.
- **Leaving is deletion,** on the server, not hiding.
- **The Worker logs no IP addresses and no request bodies.** Cloudflare itself still sees IPs to serve the request.

## 6a · Security, for an open-source client and server

Everything here is public: the endpoints, the signed text, the caps. Nothing may depend on that staying secret, and nothing secret is in the repo: the Cloudflare account token lives only in a protected deploy environment, `.dev.vars` is git-ignored, and the `database_id` in `wrangler.jsonc` is useless without the token.

| Threat | Mitigation | Owner |
|---|---|---|
| Posting as someone else | Every write is Ed25519-signed by the member's key; the member is found by `X-Member` and the signature checked against **their** key, so a swapped header fails | Worker |
| Replaying a captured request | Method, path, query, timestamp, nonce and the body's hash are signed; ±5 minutes; the nonce is stored **after** the signature verifies, in one insert that fails on a repeat | Worker |
| Stored XSS through the board | Usernames are `[A-Za-z0-9_-]{3,20}`; providers `[a-z0-9-]{1,32}`; the board page writes text with `textContent`, never `innerHTML` | Worker, board page |
| Name squatting and impersonation | Unique ignoring case; a reserved list (`admin`, `claudebar`, `tddworks`, `anthropic`, `openai`, `support`, …); an admin can hide a member | Worker |
| Spam joins, rename churn, oversized uploads | Per-IP rate limits on `POST /join` and `PATCH /me`; bodies over 64 KB refused; at most 400 rows per upload | Worker |
| Fake totals from a modified client | **Not preventable**: totals are self-reported. Per-row cap, future and stale days refused; no prizes ride on the board | accepted |
| Learning that a hidden name exists | `POST /join` answers "taken" for it. Accepted: the name is all it reveals | accepted |
| Calling signed routes from a web page | CORS headers only on `GET /board` | Worker |
| IPs and bodies in logs | Workers invocation logs off; the Worker never logs a body, a signature or a key | Worker |
| The private key read off the Mac | Keychain in release builds. A locally built, ad-hoc signed app can't use the Keychain, so the key falls back to UserDefaults, as Notify!'s token does; the worst a stolen key does is post as you on the board | App |
| CI leaking the deploy token | Worker tests run on `pull_request` without secrets; deploys run only on pushes to `main`, behind a protected environment, never `pull_request_target` | CI |
| Expensive public queries | `period` is a closed set, `provider` validated, every statement prepared; board answers cached five minutes | Worker |

## 7 · Architecture

A destination, not a provider, so it sits beside Notify! (AGENTS.md: destinations get standalone repositories, never under `ProviderSettingsRepository`).

```
┌──────────────────────────────────────────── THIS MAC (Swift) ─────────────────────────────────────────────┐
│                                                                                                           │
│  Modules (data + generic engine)               Sources/Domain/Leaderboard              Sources/App        │
│  ┌─────────────────────────────────┐          ┌────────────────────────────────┐     ┌────────────────┐  │
│  │ codex.json  + usageHistory      │          │ LeaderboardMembership (root)   │◀────│ Leaderboard    │  │
│  │  sessions/**/rollout-*.jsonl,   │          │  username, sharing, visible,   │     │  popover tab   │  │
│  │  token_count lines              │          │  lastUpload, key               │     │ LeaderboardPane│  │
│  │ UsageLog.Tokens                 │          │  dailyTokens(from:in:) ◀─── LAW: only shared        │  │
│  │  inputIncludesCacheRead (rule)  │          │  join · share · leave …        │     └───────┬────────┘  │
│  └───────────────┬─────────────────┘          ├────────────────────────────────┤             │           │
│                  ▼                            │ Username · DailyTokens ·       │             │           │
│  Account.usageHistory ──days(in:)──▶ per login│ BoardView · Standing           │             │           │
│   (Claude, Codex, Mistral)                    │ LeaderboardUploader (hourly) ◀─┼── App driver timer      │
│                                               │ RequestSigner (canonical)      │                         │
│                                               ├─ @Mockable ports ──────────────┤                         │
│                                               │ LeaderboardAPI                 │                         │
│                                               │ SigningKeyStore                │                         │
│                                               │ LeaderboardSettingsRepository  │                         │
│                                               └───────────────┬────────────────┘                         │
│  Sources/Infrastructure/Leaderboard                           │                                          │
│   LeaderboardHTTPClient (NetworkClient) · KeychainSigningKeyStore (+ UserDefaults fallback)             │
│   JSONSettingsRepository: leaderboard.* keys in ~/.claudebar/settings.json                               │
└───────────────────────────────────────────────────────────────┼──────────────────────────────────────────┘
                                          HTTPS, Ed25519-signed │
┌────────────────────────────────── Server/leaderboard (TypeScript) ────────────────────────────────────────┐
│  Cloudflare Worker: POST /join · PUT /usage · GET /me(/export) · PATCH /me · DELETE /me · GET /board      │
│   verify(signature, exact bytes) → nonce/timestamp → plausibility → D1 (prepared statements)              │
│  D1 migrations: members · daily_tokens · nonces              tests: vitest + workers pool (local D1)      │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
   docs/leaderboard/index.html (GitHub Pages) ── GET /board ──▶ public standings
```

| Component | Purpose | Notes |
|---|---|---|
| Codex `usageHistory` (JSON) | Codex daily tokens from its session logs | Each `token_count` line's `last_token_usage`, deduplicated by the session's running total (Codex writes some lines twice). No cost: the lines name no model |
| `UsageLog.Tokens.inputIncludesCacheRead` | Generic engine rule | A log whose input count already holds its cache reads; the engine takes them out, so input means the same for every provider |
| `LeaderboardMembership` | The laws of §4 on this Mac | Only ticked providers leave; only providers with usage history can be ticked; a provider's logins are summed |
| `RequestSigner` | The canonical string, signed with CryptoKit Ed25519 | Pinned by `Server/leaderboard/test/vectors.json`, read by both suites |
| `LeaderboardUploader` + App driver | Uploads 30 days on join, then hourly from `lastUpload` | `lastUpload` moves only on success |
| Worker + D1 | The server's laws of §4 | Tested locally against a simulated D1; creating the database and deploying are manual steps |

| Piece | Home |
|---|---|
| `LeaderboardMembership`, `DailyTokens`, `Username`, `BoardView`, `Standing`, `LeaderboardUploader` | `Sources/Domain/Leaderboard/` |
| `@Mockable` ports `LeaderboardAPI` and `SigningKeyStore`; plain `LeaderboardSettingsRepository` (like Notify!'s) and `@MainActor` `TokenLogs`, faked in tests | `Sources/Domain/Leaderboard/` |
| `LeaderboardHTTPClient`, `CredentialSigningKeyStore`; settings as `leaderboard.*` in `JSONSettingsRepository` | `Sources/Infrastructure/` |
| `Leaderboard` (wiring + hourly timer), `MonitorTokenLogs`, popover tab, `LeaderboardPane` | `Sources/App/` |
| Worker + D1 migrations + its tests | `Server/leaderboard/`, with its own job in `tests.yml` |
| Board page | `docs/leaderboard/` on GitHub Pages |

## 8 · Build sequence

Test-first slices, each green on its own. All nine are built; deployment is the remaining step.

1. **`Username` and `DailyTokens`.** Pins the name rule against the shared vectors, and that a `DailyUsageStat` becomes four counts and nothing else.
2. **`LeaderboardMembership` sharing.** Pins: an unticked provider never appears in `dailyTokens`; a provider without usage history can't be shared; two logins of one provider sum into one day.
3. **Request signing.** Pins the canonical string and a signature against fixed vectors, shared with the Worker.
4. **Worker: join, upload, board.** Pins: bad signature 401, replay 401, stale timestamp 401, re-upload replaces, future day 400, hidden member off the board, ties by username.
5. **Worker: `/me`, rename, hide, delete.** Pins: delete removes every row; a member can only ever read their own rows.
6. **`LeaderboardUploader`.** Pins: join uploads 30 days; an hourly upload resumes from `lastUpload`; a failed upload doesn't move `lastUpload`.
7. **Leaving.** Pins: the key is forgotten only after the server's 2xx; a failed delete leaves the member joined and says so.
8. **App surfaces.** Popover tab and Settings pane, per the design concept.
9. **Board page** on GitHub Pages.

Each user-visible slice adds its CHANGELOG line; the feature's `README.md` lands with slice 8.

## 9 · Open questions

- **More than one Mac per username?** v1 is one: the key is per install, and a second Mac's upload would replace the first's days. Supporting it means a device column in the key and the row.
- **Losing the key.** A reinstall or a lost Keychain item locks a member out of their name. A recovery code shown once at join, or a manual reset by an admin?
- **Web login.** v1 shows your data in the app and offers Export. A one-time link from the app to a short web session is designed in outline and deferred.
- **Spam and abuse.** Rate limit on `POST /join` per IP is designed. Cloudflare Turnstile, a username blocklist, and an admin hide are not yet decided.
- ~~**Where does the Worker's code live?**~~ In this repo, `Server/leaderboard/`, with its own CI job. Decided by the maintainer so app and server change in one PR.
- ~~**Rank by what?**~~ Total tokens: input + output + cache write + cache read. Decided by the maintainer; output-only stays an option if cache-heavy totals feel unfair.
- ~~**Codex tokens?**~~ In v1: Codex gets a `usageHistory` read from its session logs, needing the generic `inputIncludesCacheRead` rule.
- ~~**What does "today" mean across time zones?**~~ Each member's own date: every upload carries the Mac's `today`, believable within a day of UTC's, and that member's periods end on it.
- ~~**Mistral keeps only totals?**~~ `DailyTokens.unsplit` carries tokens a log doesn't split, so they still count.
- ~~**Where is the data stored?**~~ Cloudflare D1 behind a Worker. Settled because writes must pass server checks (a database the app writes to directly would need a secret in an open-source app), and D1's SQL answers a board view in one `GROUP BY` within the free tier.
- ~~**Can someone use a public key to act as another member?**~~ No. A public key only verifies; signing needs the private half, which never leaves its Mac.
