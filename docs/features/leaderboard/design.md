---
description: Contributor design for the Leaderboard. Join with a username, share daily token totals from chosen providers, see your rank. Covers the model, its laws, the signed API contract, privacy and the build order.
---

# Leaderboard: design

**Status:** BUILT on `feat/leaderboard-app`. The server is deployed at `https://claudebar-api.tddworks.com`; its code, storage and security internals live in the private repo `tddworks/claudebar-server`. User guide: [README.md](README.md). The screens are drawn in [design-concept/leaderboard/index.html](../../../design-concept/leaderboard/index.html). This document is the contract the build follows; where code later disagrees, the code is behind until this document says otherwise.

This document owns **joining the board, what a member shares, how a member's uploads are trusted, and how standings are ranked**. Its neighbours own the rest:

| For | Read |
|---|---|
| How a day's tokens are read from a tool's logs, and deduplicated | [daily-usage/design.md](../daily-usage/design.md) · [dedup.md](../daily-usage/dedup.md) |
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
  "Leaderboard in ClaudeBar"            ← on/off is a pause, neither hiding nor leaving
  "Turn off ▾"                          ← one way out in the tab: globe, pause, or leave
```

Two findings fall out of these. A rank is never a property of a member alone; it is a member's place in one **board view** (period × provider). And "leave" and "hide" are different acts: hiding keeps your rows and your own rank, leaving destroys both. Turning the Leaderboard **off** is a third: it changes nothing on the server, only stops this Mac taking part.

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
| **On / off** | Whether ClaudeBar takes part in the Leaderboard at all: its tab, and uploads. On until turned off, joined or not. Off is a **pause**: a member keeps their name, key and uploaded days, and their row stays on the board with its last totals | *visible* (a server fact) and *leaving* (deletion) |
| **Signing key** | The Ed25519 key pair made on join. Private half on this Mac, public half on the server | an API token; there is no shared secret anywhere |

"Daily tokens" is chosen over the user's "token usage" because *usage* already means quota usage everywhere else in ClaudeBar. Do not rename it back.

## 2 · The aggregate, from the root down

Two aggregates, one on each side of the wire. Neither reaches into the other; they meet only in the API.

```
LeaderboardMembership                     this Mac's membership (aggregate root, app)
 ├─ username : Username?                  nil = not joined; the only "joined" flag
 ├─ sharing : Set<ProviderID>             ONLY PROVIDERS WITH USAGE HISTORY
 ├─ isVisible : Bool                      hidden members still see their own standing
 ├─ isOn : Bool                           OFF = PAUSED: NO TAB, NOTHING UPLOADED; NAME, KEY, DAYS KEPT
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
| **Owns: a turned-off Leaderboard uploads nothing** | `uploadCredentials` is `nil` while off, so the uploader has nothing to sign with and `lastUpload` stays where uploads stopped |
| **Tell it** | `join(as:sharing:)` · `share(_:)` · `stopSharing(_:)` · `setVisible(_:)` · `rename(to:)` · `leave()` · `turnOff()` · `turnOn()` |
| **It answers** | `isJoined` · `isOn` · `sharing` · `myStanding(in:)` |
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

// The driver checks every few minutes and when the Mac wakes; the uploader decides
// whether an hour has passed by the clock (driver, like NotifyPublishDriver).
await uploader.uploadDue()                       // asks the membership for its days; never filters itself

// An upload you asked for always goes: Refresh (on any tab), joining,
// switching a shared provider on or off.
await uploader.uploadNow()

// Settings
membership.share(.mistral)                       // throws if Mistral has no usage history on this Mac
membership.setVisible(false)
try await membership.leave()                     // server deletes first, then the key is forgotten

// On / off: a pause, kept on this Mac only. The server hears nothing.
leaderboard.turnOff()                            // tab gone, uploads stop; says so once in the popover
leaderboard.turnOn()                             // tab back; uploads now, from where they stopped

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
| A provider's day is the sum of all its logins on this Mac; days without tokens aren't sent | `DailyTokens.summed`, which both the upload and the join form's preview use, so the preview is exactly what is sent |
| Your private key never leaves your Mac and is never logged | `SigningKeyStore` (Keychain, with the UserDefaults fallback Notify! uses for ad-hoc builds) |
| Uploading a day again replaces it; it never adds | Server |
| A missed hour, or a Mac asleep for days, heals on the next upload | `LeaderboardUploader`: uploads from the day of `lastUpload` to today, at most 30 days, and on join the last 30 |
| Uploads stay hourly by the clock, even after the Mac sleeps | `LeaderboardUploader.uploadDue()`: uploads only when there is no `lastUpload` or it is at least an hour old by the wall clock. The App driver only asks often (every 5 minutes and on wake) and never decides |
| An upload you asked for always goes, hour or not | `LeaderboardUploader.uploadNow()`: Refresh in the popover, whatever tab is open, joining, and switching a shared provider |
| Every write and every private read is signed by the member's key | Server |
| Who you are comes from the verified signature, never from a parameter | Server |
| A signed request is accepted once, and only within 5 minutes of its timestamp | Server |
| A username is unique ignoring case | Server |
| A username is 3–20 of `A–Z a–z 0–9 - _` | **Two owners, deliberately:** `Username` for instant feedback, the server as authority. Both check the same `vectors.json`, so they cannot drift silently |
| No future days, nothing older than 30 days, no day above the plausibility cap | Server |
| Standings rank by total tokens (the five counts summed); ties by username | Server |
| A member's period ends on their own date, the one their Mac sent with its last upload, while it is within a day of UTC's | Server |
| A hidden member is absent from the public board and still sees their own standing | Server |
| Your own upload shows on the board you read at once, the same place *Your rank* says; everyone else's within two minutes | Server (an upload drops the boards it changes from the edge cache) |
| The globe shows only countries, only for members who opted in; tokens only where at least three are | Server |
| A member who hasn't opted in sees the globe offered once, until they opt in or dismiss it | `LeaderboardMembership.showsGlobeHint` |
| A shared rank image shows one standing in one board view (rank, where that is, tokens, the provider mix) and no other member's name; there is none to share before a rank | `RankCard` |
| *Top N%* only in the top half, where N is the rank over every member, rounded up; *#r of N* below it; *Top 100* on a board longer than it lists; nothing when the rank isn't among the members listed | `RankCard.placement` |
| A profile link is a platform and a handle that fits its rules, never a URL | `ProfileLink` (the app, as you type) and the server (the authority); one `vectors.json` |
| Leaving deletes the member and every row, on the server | Server — the app forgets the key only after a 2xx |
| A turned-off Leaderboard uploads nothing, joined or not, and keeps the membership as it was | `LeaderboardMembership.uploadCredentials` (nil while off) |
| Turned off stays off across launches, and outlives leaving and joining again | `LeaderboardMembership.isOn`, kept as `leaderboard.on` apart from the membership record |
| Turning it back on catches up the days missed, up to 30 | `LeaderboardUploader`'s range from `lastUpload`, unchanged; `Leaderboard.turnOn()` asks for it at once |
| While off there is no Leaderboard tab, and the popover falls back to its provider | The popover reads `membership.isOn` |

## 5 · The API

Host: `https://claudebar-api.tddworks.com`; the public board page is `https://claudebar.tddworks.com/leaderboard`, which reads `/board` from its own origin. The server's code, storage and limits are private (`tddworks/claudebar-server`); this section is the contract the app relies on.

| Route | Auth | Does |
|---|---|---|
| `POST /join` `{username, publicKey}` | none, rate-limited per IP | creates the member, or `409` if the name is taken |
| `PUT /usage` `{today, days: [DailyTokens]}` | signed | upserts each day; `today` is the Mac's date, refused when more than a day from UTC's |
| `GET /me` | signed | the member, their standing in a view, every row they uploaded |
| `GET /me/export` | signed | the same, as a downloadable JSON file |
| `PATCH /me` `{username?, visible?, shareCountry?, link?}` | signed | rename, hide or show; opt in to the globe (the server then keeps the country Cloudflare's edge reports for that request, and never updates it) or out (it forgets it at once); set the profile link as `{platform, handle}` (`x`, `instagram` or `github`, each with its own username rule, pinned by `vectors.json`) or remove it with `null` |
| `DELETE /me` | signed | deletes the member and every row |
| `GET /globe?period=30d` | none | every country opted-in members share; members and tokens (`countries`) only where at least 3 are, the rest named without a number (`present`, A–Z) |
| `GET /board?period=7d&provider=claude` | none | standings of visible members, up to 100, cached at the edge for two minutes, dropped from the uploader's data centre by each `PUT /usage`; the app reads it without its local HTTP cache |

**Signing.** On join the app makes a `Curve25519.Signing.PrivateKey` (CryptoKit) and sends its public half. Every signed request carries:

```
X-Member:    <username>
X-Timestamp: <unix seconds>
X-Nonce:     <16 random bytes, base64url>
X-Signature: base64url( sign( METHOD \n PATH?QUERY \n TIMESTAMP \n NONCE \n hex(SHA256(body bytes)) ) )
```

The Worker verifies with WebCrypto's Ed25519 against the stored public key, over **the exact bytes received**, never re-serialised JSON. The canonical string is pinned by `Tests/DomainTests/Leaderboard/vectors.json`, of which the server keeps an identical copy.

CryptoKit's Ed25519 signatures are randomised, so the shared vectors are **verified** on both sides, never compared byte for byte.

## 6 · Privacy

The second destination after Notify! that sends ClaudeBar's own state outward, so the same rules apply, stated plainly:

- **What leaves the Mac:** the username, and per shared provider per day four token counts. No cost, no model names, no projects, no paths, no prompts, no account email.
- **Where it goes:** a Cloudflare Worker run by tddworks, and from there to a public page if visible.
- **Off by default.** Nothing is sent until the user joins, and only for providers they tick.
- **A profile link is optional, and only a handle.** A member may add one X, Instagram or GitHub handle; the address is always built from the platform's own base, never typed. It is not verified, and every place it shows says so.
- **The globe is opt-in, and only a country.** With *Show my country on the globe* on, the server keeps the two-letter country Cloudflare's edge sees the request that turned it on come from, once: later requests don't change it, or a VPN's exit would move the member from call to call; the Mac sends no location and asks for none. Never a city, coordinates or the IP. Publicly a country is named from its first member; its members and tokens are totalled only where at least three are, and the web board's tokens-on-the-globe figure adds up only those totals, never a number that, less the shown ones, would be one member's own. Turning it off forgets the country at once.
- **Leaving is deletion,** on the server, not hiding.
- **The Worker logs no IP addresses and no request bodies.** Cloudflare itself still sees IPs to serve the request.

## 6a · Security, as the app sees it

Nothing the app relies on depends on the server's code staying secret, and the app holds no secret but its own key.

- **Only you can post as you.** Every write and private read is signed with an Ed25519 key made on this Mac; the server holds only the public half, which can check a signature but never make one. Who you are comes from the verified signature, never from a parameter.
- **A captured request can't be replayed.** The signature covers the method, path, query, time, a one-time nonce and the body's hash, and the server accepts it once, within five minutes.
- **The key stays on the Mac.** It lives in the Keychain in release builds. A locally built, ad-hoc signed app can't use the Keychain, so the key falls back to UserDefaults, as Notify!'s token does; the worst a stolen key does is post as you on the board.
- **Totals are self-reported.** A modified client can inflate its own numbers; the server refuses implausible days, and no prizes ride on the board.
- **The server may forget a member** who joined and never uploaded; the app then forgets the membership too and shows the join form again (`LeaderboardUploader`).

The server's own threat model (rate limits, caching, moderation, logging) is in `tddworks/claudebar-server`, `leaderboard/DESIGN.md`.

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
│   (Claude, Codex, Mistral, Oh My Pi)          │ LeaderboardUploader (hourly) ◀─┼── App driver timer      │
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
┌──────────────────────────── Leaderboard server (private: tddworks/claudebar-server) ──────────────────────┐
│  https://claudebar-api.tddworks.com — the API contract in §5; its insides are documented in that repo     │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
   claudebar.tddworks.com/leaderboard — the public board page
```

| Component | Purpose | Notes |
|---|---|---|
| Codex `usageHistory` (JSON) | Codex daily tokens from its session logs | Each `token_count` line's `last_token_usage`, deduplicated by the session's running total (Codex writes some lines twice). No cost: the lines name no model |
| `UsageLog.Tokens.inputIncludesCacheRead` | Generic engine rule | A log whose input count already holds its cache reads; the engine takes them out, so input means the same for every provider |
| `LeaderboardMembership` | The laws of §4 on this Mac | Only ticked providers leave; only providers with usage history can be ticked; a provider's logins are summed |
| `RequestSigner` | The canonical string, signed with CryptoKit Ed25519 | Pinned by `Tests/DomainTests/Leaderboard/vectors.json`; the server checks an identical copy |
| `LeaderboardUploader` + App driver | Uploads 30 days on join, then hourly from `lastUpload`, and now when you ask | `lastUpload` moves only on success. The driver asks `uploadDue()` every 5 minutes and on `NSWorkspace.didWakeNotification`; a `Timer`'s clock stops while the Mac sleeps, so the hour is the uploader's to judge |
| Server | The server's laws of §4 | Private repo `tddworks/claudebar-server`; deployed with the `cf` CLI |

| Piece | Home |
|---|---|
| `LeaderboardMembership`, `DailyTokens`, `Username`, `BoardView`, `Standing`, `RankCard`, `LeaderboardUploader` | `Sources/Domain/Leaderboard/` |
| `@Mockable` ports `LeaderboardAPI` and `SigningKeyStore`; plain `LeaderboardSettingsRepository` (like Notify!'s) and `@MainActor` `TokenLogs`, faked in tests | `Sources/Domain/Leaderboard/` |
| `LeaderboardHTTPClient`, `CredentialSigningKeyStore`; settings as `leaderboard.*` in `JSONSettingsRepository` | `Sources/Infrastructure/` |
| `Leaderboard` (wiring, the 5-minute check and the wake observer, `refresh()` for the popover's Refresh, `share(_:)` for *Share my rank*, `turnOff()`/`turnOn()` and the one-time `offNotice`), `MonitorTokenLogs`, popover tab, `RankCardImage` (the image, in the member's theme) and `RankShareOverlay`, `TurnOffMenu` (the tab's *Turn off ▾*, drawn in the popover's top layer so the scroll view never clips it), `LeaderboardPane` | `Sources/App/` |
| Server and board page | Private repo `tddworks/claudebar-server` |

## 8 · Build sequence

Test-first slices, each green on its own. All nine are built; deployment is the remaining step.

1. **`Username` and `DailyTokens`.** Pins the name rule against the shared vectors, and that a `DailyUsageStat` becomes four counts and nothing else.
2. **`LeaderboardMembership` sharing.** Pins: an unticked provider never appears in `dailyTokens`; a provider without usage history can't be shared; two logins of one provider sum into one day.
3. **Request signing.** Pins the canonical string and a signature against fixed vectors, shared with the Worker.
4. **Worker: join, upload, board** (in `tddworks/claudebar-server`). Pins: bad signature 401, replay 401, stale timestamp 401, re-upload replaces, future day 400, hidden member off the board, ties by username.
5. **Worker: `/me`, rename, hide, delete** (in `tddworks/claudebar-server`). Pins: delete removes every row; a member can only ever read their own rows.
6. **`LeaderboardUploader`.** Pins: join uploads 30 days; an hourly upload resumes from `lastUpload`; a failed upload doesn't move `lastUpload`; `uploadDue()` skips when `lastUpload` is under an hour old by the clock and uploads once it is an hour or more; `uploadNow()` uploads regardless.
7. **Leaving.** Pins: the key is forgotten only after the server's 2xx; a failed delete leaves the member joined and says so.
8. **App surfaces.** Popover tab and Settings pane, per the design concept.
9. **Board page** on GitHub Pages.
10. **On / off.** Pins: off uploads nothing and keeps the membership; off is remembered across launches and outlives leaving; back on uploads from `lastUpload`. Surfaces per [the mockup](../../../design-concept/leaderboard/index.html) (*5 · Turn it off*): the first card in Settings, *Not for me · hide Leaderboard* under the join form, and *Turn off ▾* on the tab's globe line with *My country on the globe* (while on it), *Leaderboard: pause & hide* and *Leave and delete my data…*.

Each user-visible slice adds its CHANGELOG line; the feature's `README.md` lands with slice 8.

## 9 · Open questions

- **More than one Mac per username?** v1 is one: the key is per install, and a second Mac's upload would replace the first's days. Supporting it means a device column in the key and the row.
- **Losing the key.** A reinstall or a lost Keychain item locks a member out of their name. A recovery code shown once at join, or a manual reset by an admin?
- **Web login.** v1 shows your data in the app and offers Export. A one-time link from the app to a short web session is designed in outline and deferred.
- **Spam and abuse.** Rate limit on `POST /join` per IP is designed. Cloudflare Turnstile, a username blocklist, and an admin hide are not yet decided.
- ~~**Where does the Worker's code live?**~~ In the private repo `tddworks/claudebar-server` (moved 2026-10-04 by the maintainer). The app and the server share `vectors.json`; change both copies together.
- ~~**Rank by what?**~~ Total tokens: input + output + cache write + cache read. Decided by the maintainer; output-only stays an option if cache-heavy totals feel unfair.
- ~~**Codex tokens?**~~ In v1: Codex gets a `usageHistory` read from its session logs, needing the generic `inputIncludesCacheRead` rule.
- ~~**What does "today" mean across time zones?**~~ Each member's own date: every upload carries the Mac's `today`, believable within a day of UTC's, and that member's periods end on it.
- ~~**Mistral keeps only totals?**~~ `DailyTokens.unsplit` carries tokens a log doesn't split, so they still count.
- ~~**Where is the data stored?**~~ Cloudflare D1 behind a Worker. Settled because writes must pass server checks (a database the app writes to directly would need a secret in an open-source app), and D1's SQL answers a board view in one `GROUP BY` within the free tier.
- ~~**Can someone use a public key to act as another member?**~~ No. A public key only verifies; signing needs the private half, which never leaves its Mac.
