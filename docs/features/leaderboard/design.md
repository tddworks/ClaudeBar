---
description: Contributor design for the Leaderboard. Join with a username, share daily token totals from chosen providers, see your rank. Covers the model, its laws, the signed API contract, privacy and the build order.
---

# Leaderboard: design

**Status:** BUILT on `feat/leaderboard-app`. The server is deployed at `https://claudebar-api.tddworks.com`; its code, storage and security internals live in the private repo `tddworks/claudebar-server`. User guide: [README.md](README.md). The screens are drawn in [design-concept/leaderboard/index.html](../../../design-concept/leaderboard/index.html). This document is the contract the build follows; where code later disagrees, the code is behind until this document says otherwise. **Several devices per member ([§2a](#2a--devices-one-member-several-machines)) is built on the server, not yet in the app**, asked for in [#507](https://github.com/tddworks/ClaudeBar/issues/507); until the app has it, a member is one key on one Mac.

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

**A member shares the daily token totals of the providers they chose, from each of their devices, each upload signed by a key only that device holds, and the board ranks members by those totals over a period.**

```
   each device (a Mac, a PC)                  the server (Worker + D1)
 ┌──────────────────────────────┐   signed   ┌────────────────────────────┐
 │ Membership                   │ ─────────▶ │ members   (username)       │
 │  key, sharing, refused       │  PUT /usage│ devices   (key, label)     │
 │ UsageHistory per login ──▶   │            │ daily_tokens (one row per  │
 │   DailyTokens per provider   │ ◀───────── │   member·device·provider·  │
 └──────────────────────────────┘ GET /board │   day)                     │
                                            │ standings  (ranked view)   │
                                            └────────────────────────────┘
```

---

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Board** | The ranking, as one public page and one popover tab | a provider's *dashboard* link |
| **Member** | Someone who joined: a username on the server, with one to five devices | a provider *account* (a login); a member may have several logins per provider |
| **Membership** | One device's side of being a member: its key, what it shares, and a copy of the member's name and settings | the server's member row, which never holds a private key |
| **Device** | One machine of a member: its own key, a label, the days it uploaded. *Removed* means its key no longer signs; its days stay until deleted | a provider *account*; "this Mac" in v1, which is one device |
| **Device code** | The 8 characters a new device shows; a device the member already has approves it within 10 minutes, once | a password, or a recovery code |
| **Username** | The public name, chosen at join, unique ignoring case | an account email, which is never sent |
| **Daily tokens** | One provider's token counts for one local calendar day on one device: input, output, cache write, cache read, and *unsplit* — tokens a log keeps only as a total (Mistral) | `DailyUsageStat`, which also carries cost, sessions and working time that are never shared |
| **Sharing** | The providers a member chose to upload | a provider being *enabled* in ClaudeBar |
| **Upload** | One signed `PUT /usage` carrying days of daily tokens | a *refresh*, which fetches quotas |
| **Board view** | A period and a provider filter: `7 days · Claude` | a period alone |
| **Period** | `today`, `7d` or `30d`. Closed | an arbitrary date range |
| **Standing** | One member's place in one board view: rank, username, totals, provider mix | the member |
| **Visible** | Whether the member appears on the public board. A hidden member is still ranked for themselves | membership |
| **On / off** | Whether ClaudeBar takes part in the Leaderboard at all: its tab, and uploads. On until turned off, joined or not. Off is a **pause**: a member keeps their name, key and uploaded days, and their row stays on the board with its last totals | *visible* (a server fact) and *leaving* (deletion) |
| **Signing key** | The Ed25519 key pair a device makes when it joins or is added. Private half on that device, public half on the server; the public half is the device's identity | an API token; there is no shared secret anywhere |

"Daily tokens" is chosen over the user's "token usage" because *usage* already means quota usage everywhere else in ClaudeBar. Do not rename it back.

## 2 · The aggregate, from the root down

Two aggregates, one on each side of the wire. Neither reaches into the other; they meet only in the API.

```
LeaderboardMembership                     this device's membership (aggregate root, app)
 ├─ username : Username?                  nil = not joined; the only "joined" flag. A COPY OF THE MEMBER'S, FOLLOWS /me
 ├─ sharing : Set<ProviderID>             ONLY PROVIDERS WITH USAGE HISTORY; THIS DEVICE'S OWN
 ├─ isVisible : Bool                      hidden members still see their own standing. A COPY, FOLLOWS /me
 ├─ isOn : Bool                           OFF = PAUSED: NO TAB, NOTHING UPLOADED; NAME, KEY, DAYS KEPT
 ├─ key : SigningKey                      PRIVATE HALF NEVER LEAVES THE DEVICE
 ├─ lastUpload : Date?                    the last good upload: v1 resumes there, devices time the hour by it
 ├─ refused : Set<provider · day>         DAYS THE SERVER REFUSED, LAST 30 DAYS: SENT AGAIN WITH EACH UPLOAD
 └─ machine : hash?                       THIS MAC'S HARDWARE UUID, HASHED WITH THE KEY'S PUBLIC HALF. NEVER SENT

Board                                     the server's ranking (aggregate root, Worker)
 ├─ members : Member                      username, visible, joined at
 ├─ devices.today                        EACH DEVICE'S OWN DATE: ITS ROWS' PERIODS END ON IT
 ├─ members.suspended                    SET ONLY BY A MAINTAINER, NEVER THROUGH THE API
 ├─ devices : Device                      public key, label, added at, removed at. AT MOST 5 NOT REMOVED
 └─ dailyTokens : DailyTokens             ONE ROW PER MEMBER · DEVICE · PROVIDER · DAY
     └─ standings(view) → [Standing]      A MEMBER'S DAY IS THE SUM OF THEIR DEVICES' ROWS. RANKED BY TOTAL, TIES BY USERNAME
```

There is no `Leaderboard` type on the app side that holds standings. The app does not own the ranking, so it only asks the server for a board view and draws what comes back; caching it would give the app a second opinion about rank.

### `LeaderboardMembership`: this device's membership

> **Pointable as:** a membership card. A name on the front, a key in your pocket, and a list of what you agreed to share.

| | |
|---|---|
| **Owns: only shared providers leave the device** | `dailyTokens(from:)` drops every provider not in `sharing` before anything is built |
| **Owns: only shareable providers can be shared** | `share(_:)` refuses a provider with no usage history; the ability is absent, not ignored |
| **Owns: a turned-off Leaderboard uploads nothing** | `uploadCredentials` is `nil` while off, so the uploader has nothing to sign with and `lastUpload` stays where uploads stopped |
| **Owns: a copied key it detects never uploads unasked** | at launch, a key whose `machine` hash isn't this Mac's uploads nothing until the member answers: this Mac gets its own key, or keeps this one and records its hash ([§2a](#2a--devices-one-member-several-machines)); every key made here is recorded with this Mac's hash, and forgetting a key forgets its hash |
| **Tell it** | `join(as:sharing:)` · `share(_:)` · `stopSharing(_:)` · `setVisible(_:)` · `rename(to:)` · `leave()` · `turnOff()` · `turnOn()` · `requestToJoin(label:)` · `pendingDevice(code:)` · `approve(code:)` · `remove(device:deletingDays:)` · `deleteDays(of:provider:day:)` · `becomeOwnDevice()` · `keepKeyHere()` |
| **It answers** | `isJoined` · `isOn` · `sharing` · `devices` · `myStanding(in:)` · `refused` (days the server refused, tried again) · `holdsCopiedKey` (this Mac's key came from another Mac) |
| **Never** | holds a ranking · sends a provider it was not told to share · forgets its key before the server confirmed the leave or the removal · keeps a member setting the server has changed since |

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

## 2a · Devices: one member, several machines

**Status:** confirmed ([#512](https://github.com/tddworks/ClaudeBar/pull/512)). The server side, slice 11, is built (`tddworks/claudebar-server` #1); the app side, slices 12–15, is not. It will be written in Kotlin in ClaudeBarKit's `leaderboard` package ([#507](https://github.com/tddworks/ClaudeBar/issues/507)).

People code on more than one machine: a MacBook, a Mac mini, a Windows PC. A tool's logs hold only what ran on that machine, so a member's day is the sum of their machines' days. v1 can't express that: the key is per install, a second Mac can't join under a name already taken, and a copy of one Mac's key on another makes their uploads replace each other's days (§9).

### A device is a key

Each device makes its own key and keeps the private half where its platform keeps secrets: the Keychain, with §4's fallback, on a Mac; Credential Manager or DPAPI on Windows ([#507](https://github.com/tddworks/ClaudeBar/issues/507)). Every signed request also carries the public half as `X-Key`. The server finds the device by its key, and the member through the device. It never uses `X-Member` for this: a rename on one device would leave that header stale on the others, and today a stale name is answered `401`, after which the app forgets its membership (`LeaderboardUploader`). The signed string doesn't change, so `vectors.json`'s signing cases don't either.

A client from before devices sends no `X-Key`. The server then finds the member by `X-Member`, and the device by whichever of the member's keys verifies the signature. Such a client still loses its membership when another device renames the member, as in v1. Its device stays in the list until removed, and its days count; once that Mac is updated and added again, the member removes the old entry.

Why not copy one key to every machine:
- The private half would leave its device.
- The server couldn't tell the machines apart, so their days would replace each other, which is v1's problem again.

### Adding a device: the new one shows a code, one you have approves it

This is RFC 8628's device flow, the one GitHub's and Microsoft's sign-ins use. Keybase and WhatsApp link the same way: a device the person already has vouches for the new one.

1. **On the new machine**, the join form's *Already a member? Add this Mac*:
   - It makes its key and sends `POST /devices {publicKey, label}`. The label is filled in with the Mac's model, never its computer name (§6).
   - The server answers with a code: 8 characters of RFC 8628's `BCDFGHJKLMNPQRSTVWXZ`, shown as `WDJB-MJHT`, good for 10 minutes and once.
2. **On a device already joined**, *Add a device*, then type the code:
   - It first reads what the code would add (`GET /me/devices/pending/{code}`: the label, and when it asked) and shows that above **Approve**. RFC 8628 §5.4 asks for this, so a code read out to a stranger isn't approved blind.
   - **Approve** sends `POST /me/devices {code}`, signed.
3. **The new machine** asks `GET /me` every 5 seconds, signed with its own key. The signature proves it holds the key it asked with, nothing more: until the code is approved, the answer carries no member data.
   - `202` while it waits; the member once approved; `401` once the code expired.
   - Once approved, it names the member it joined (`@name`) and asks before anything is sent: a code that leaked, in a screenshot say, could have been approved by someone else. Then it ticks what it shares and uploads its last 30 days, as a join does.
4. **Every other device in use past its first week** shows each device added since it last looked, once, with its label and **Remove** beside it. It looks on `/me`, which it reads after each upload and when the Leaderboard tab opens. A device that's turned off sees it when turned back on, and one in its own first week sees it once that week ends: until then `/me` shows it only itself. Telegram asks a member's other sessions the same about a new login ([core.telegram.org/api/auth](https://core.telegram.org/api/auth)).

**Limits.**
- Approving, and reading a pending code, are limited to 10 a minute per member (Cloudflare's limiter counts only 10 s or 60 s periods; at that rate a live code can't be found among 20⁸ in its 10 minutes); asking for codes, per IP, as `POST /join` is.
- A member has at most 5 devices that aren't removed (Signal links 5, WhatsApp 4). A sixth approve is refused (`409 deviceLimit`).

### What a new device may do: a waiting week

For its first 7 days a device that was *added* uploads and changes only its own days and settings. It reads only those too, with the member's settings and standing: on `/me` it gets the member's name, visibility, globe and link, its standing in a view, which the board already shows for a visible member, and its own device and rows, but not the other devices or their rows; `/me/export` is `403 deviceTooNew`. A phished device so learns no more than the member's total before it can be seen and removed. The device that joined isn't held back: it is the member, and there is no one else to protect it from. An added device can't do these until then (`403 deviceTooNew`):
- rename or hide the member, or change its globe or link;
- approve a device, or remove another one (removing itself is allowed);
- delete a removed device's days;
- leave.

Without this, a device approved by mistake, or a phished code (RFC 8628 §5.4), could remove every other device before anyone noticed. Each would forget its membership on its next upload, and the name would be the stranger's.

The rule follows what the research found:
- Products rank devices. WhatsApp deletes an account only from the primary phone ([faq](https://faq.whatsapp.com/2138577903196467)), and Signal and WhatsApp link only from it.
- Apple delays changes that could lock you out ([Stolen Device Protection](https://support.apple.com/en-us/120340)).
- ClaudeBar has no primary to name, so age stands in for it: the week is long enough for the notice in step 4 to be seen on a machine used weekly.
- A device past its first week, or a stolen key of one, can do everything the member can, as a v1 key could post and leave.

Below, *past its first week* means the device that joined, or one added 7 days ago or more.

### Removing a device revokes its key, and only that

`DELETE /me/devices/{key}` works from any device of the member past its first week, and from the device itself.
- The removed device's next upload is answered `401` with `"error": "unauthorized"`, so even an app from before devices forgets its membership, as it does today when the server forgot its member. The answer also names the device that removed it (`removedBy: {publicKey, label}`), and a current app says so.
- Removing itself, a device forgets once the server confirmed, as leaving does.
- Its uploaded days stay and keep counting, listed under it as *removed*. Google, Apple, Microsoft, Tailscale and Keybase all remove a device this way: its access goes, the account's data doesn't.
- The last device can't be removed (`409 lastDevice`). That is leaving, which deletes the member, every device and every row.

**Remove and delete its days.** When a device removes *another* device that is still in its first week, the dialog offers **Remove** and **Remove and delete its days** side by side. The second removes the device, then deletes its days (`DELETE /me/devices/{key}/days`, below); if that second request fails, the device is removed all the same and its days can be deleted from the list. A stranger's device approved by mistake can fill the member's cap with made-up days, and the cap then refuses whichever device uploads last, which is the member's real ones ([Counting, and its bound](#counting-and-its-bound)). Deleting its days frees the cap, and the refused days come back on the next uploads. It is a choice the member sees, so deleting is still never a side effect of removing. A device removing itself isn't offered it.

### Deleting a removed device's days

`DELETE /me/devices/{key}/days`, narrowed with `?provider=claude` and `&day=2026-10-06`, deletes a removed device's days, for one provider, one day or all, from another device of the member past its first week. For a device still in use it is `403 notYours`: that device would only send them again. Where a device can be removed, deleting its data is a separate, named action, never a side effect of removing it: Signal's *Delete Data*, WakaTime's bulk delete.

It remedies days counted twice by an old entry, after a reinstall (*Losing a key*) or a copy (*A key copied to another machine*), and a phished device's made-up days.

### What an upload sends

As in v1: every day from `lastUpload`'s day to today, at most 30 days, and the last 30 on join or once added, except a copy made its own device, which keeps the copied `lastUpload` (*A key copied to another machine*). Two things change:
- **A bad day is refused alone.** Every per-day refusal is listed under `refused` in a `2xx`, and the rest of the upload is kept: a day too old, in the future, or over the cap. An upload fails whole only for what is wrong with all of it, its signature or its clock.
- **A refused day is tried again.** The device keeps it (`refused`) and sends it with each upload until the server takes it or it is 30 days old. A day the cap pushed out comes back once the cap has room, after a phished device's days are deleted, say.

This answer is for every client, with or without `X-Key`, replacing v1's `400` for a future day. A client from before devices ignores the body and moves `lastUpload`, so it sends a refused day again only while that day is still in its range: today, or yesterday until its first upload after midnight. A refused day that has left its range is what it loses. Answered `400`, it would lose more: once other devices' rows put one of its days over the member's cap, its whole upload would fail every hour, `lastUpload` would never move (`LeaderboardUploader.uploadNow()`), and none of its 30 days would get through.

### Counting, and its bound

A member's provider-day is the sum of their devices' rows, each device's day being its own local day. The plausibility cap bounds that sum, so five devices, or five copies of one log folder, can claim no more than one device could.
- **The upload that crosses the cap:** the server refuses that one provider-day and keeps the rest, listing it under `refused`. The device says which day and why, and tries it again on later uploads (above).
- **Which device is refused:** whichever uploads last; the cap has no other way to choose.

That bound is the defence, with the maintainer's `suspended`, whatever the devices:
- §6a's "a modified client can inflate its own numbers" holds unchanged, and so does writing logs by hand. Either defeats any check made on the client's side.
- Google Play Games' score limits and Strava's flags end at the same pair, bounds plus review. So do the Claude Code leaderboards, viberank and tokscale, which hide or delete by hand. None of them observes the usage itself.
- Steam can do better only where the game's own server writes the score ("Writes: Trusted").

### Two devices reading the same logs count twice, and nothing is subtracted

- **How it happens:** a log folder synced between machines, or a folder copied on purpose. A reinstall or a migration is handled below.
- **Why the server can't take them out:** no log says which machine wrote a record. A Claude line carries `cwd`, `sessionId`, `version`; Codex's `session_meta` carries `cwd`, `cli_version`. The server sees only daily totals.
- **Why the app doesn't send more to find them:** exact removal needs every record (Splitrail Cloud uploads a hash per message), which would end §6's "four token counts per provider per day".
- **Why no rule lowers a number on a guess:** a sum of two daily totals can't tell shared records from coincidence. Two devices sharing 10,000 one-token calls, each with one distinct million-token call, both show 1,010,000 tokens, yet together they used 2,010,000. Any rule that keeps one of two rows would drop a real million there.

So such days count twice, bounded by the cap. Pointing them out to the member is a follow-up (§9).

### A key copied to another machine

**How a key gets copied.**
- Migration Assistant transfers keychains, and the old Mac keeps its copy ([Keychain Access guide](https://support.apple.com/en-gb/guide/keychain-access/kyca1121/mac), [Migration Assistant](https://support.apple.com/en-us/102613)). A Time Machine restore brings back the whole account ([102551](https://support.apple.com/en-us/102551)).
- The key is a generic-password item in the file-based login keychain: SecItem without `kSecUseDataProtectionKeychain` ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)). An ad-hoc build keeps it in UserDefaults instead. Either way it comes along, with `~/.claudebar/settings.json`.
- The result is two machines that are one device, whose uploads replace each other's days, as in v1.

**How the copy knows, before it uploads.** Next to its key a device keeps a hash of its Mac's hardware UUID (`IOPlatformUUID`, in the I/O Registry's `IOPlatformExpertDevice`), salted with the key's public half, and never sends it. Every key made on a Mac, on join, when added, or by *Make this Mac its own device*, is recorded with that Mac's hash; forgetting a key, by leaving or being removed, forgets its hash too.
- The UUID is read live from the hardware's registry, not from a file, so Migration Assistant, or a restore to another Mac, brings the key and the hash but not the UUID: at launch the copy finds that the hash isn't its Mac's. Fleet hit the same Migration Assistant copy and fixed it the same way, comparing a kept hardware UUID with the live one ([fleetdm/fleet#17934](https://github.com/fleetdm/fleet/issues/17934)).
- A restore to the same Mac keeps the UUID, so nothing is asked. A repair that replaces the logic board is expected to change the UUID, unconfirmed; that Mac is asked, and answers *Keep the key here* (below).
- Keeping a hash, not the UUID, keeps a hardware id out of a settings file someone might attach to a bug report.
- A key from before this rule has no hash: the first launch with it records whichever Mac that is, so a copy made before then goes unnoticed, as in v1. If the UUID can't be read (§9), the device keeps no hash, and a copy goes unnoticed the same way.

**What the copy does.** It uploads nothing under the copied key and asks, until answered: *This Mac has a copy of «label»'s key.*
- **Make this Mac its own device**, when both Macs stay in use:
  1. It makes a new key, and the copied key, which still signs, approves it, as *Add a device* does. If the copied key is in its first week, another device of the member past its first week approves it, or the switch waits for the week to pass.
  2. It forgets the copied key, its hash and the copied `refused` days, which are the other Mac's to retry, and records this Mac's hash with the new key. It keeps the copied `lastUpload`, so its first upload under the new key starts at that day rather than 30 days back: the days before were the other Mac's, sent under the copied key already.
  3. The new key is an added device, held to its first week. The other Mac goes on as before.
- **Keep the key here**, when the other Mac is gone (a wiped or sold Mac) or this is the same Mac after a repair: it records this Mac's hash and goes on with the key, its first week and its days as they were. Chosen while the other Mac is still in use, it leaves two Macs on one key, which replace each other's days as in v1, and the other Mac doesn't notice.

**What can count twice,** after *Make this Mac its own device*: every day from the copied `lastUpload`'s day to the copy's day. Both Macs hold those days' records from before the copy, and both send them, the other Mac under the copied key and this one under its new key. They stay counted twice, bounded by the cap, as two devices reading the same logs do. If the other Mac turns out to be gone after all, the member removes it and deletes its rows for those days, from a device past its first week: for a member with no other device, once this Mac's new key is past its first week. A copy whose app is from before this rule doesn't check, and uploads as v1 would.

**Prevention instead of detection** would need a key that can't migrate: the data protection keychain with a `ThisDeviceOnly` class, which "do not migrate to a new device" ([Apple](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)). Tailscale keeps its node state that way on Apple platforms, except in its standalone macOS build ([blog](https://tailscale.com/blog/encrypting-data-at-rest)). The data protection keychain needs a provisioning profile ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)). The Mac App Store build has one (`appstore-release.yml`); the Developer ID build, the DMG and Homebrew, has none. The UUID check above needs no profile.

### Losing a key

- **With a second device past its first week**, a lost key is a device to remove from the other one and a new device to approve. Keybase and GitHub both tell people to keep a second device or method for exactly this. What happens to the old entry's days:
  - **The reinstalled Mac still has its logs:** the new device sends its 30 days, the same as the old entry's, so once the old entry is removed the member deletes its days that the new device sent again, by provider and day. Its other days stay.
  - **The logs are gone too:** the old entry's days are all that's left of them, so they stay.
- **With one device**, §9's question stands.

### What a device keeps, and what it takes from the server

- **The member's, kept as a copy:** name, visibility, globe and link. The copy follows every `/me` answer, which therefore carries `username`. A rename on the MacBook reaches the Mac mini on its next upload, and never as a stale `X-Member` that forgets it.
- **The device's own, never sent:** sharing, on/off, `lastUpload`, `refused`, the hash of its Mac's UUID, and which devices it has already shown as added. Each device ticks its own providers, pauses on its own, and uploads on its own clock.

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

// Devices (§2a). The new device shows a code; one the member already has approves it.
let code = try await membership.requestToJoin(label: "Mac mini")   // on the new machine; then it waits for approval
let pending = try await membership.pendingDevice(code: code)         // on a joined device: the label and when it asked
try await membership.approve(code: code)                             // from a device past its first week
try await membership.remove(device: oldMac, deletingDays: false)     // revokes its key; its days stay
try await membership.remove(device: stranger, deletingDays: true)    // another device in its first week: removes, then deletes its days
try await membership.deleteDays(of: oldMac, provider: "claude", day: nil) // a removed device's; never a side effect
try await membership.becomeOwnDevice()                               // the key's machine hash isn't this Mac's: Make this Mac its own device
try await membership.keepKeyHere()                                   // or: the other Mac is gone, or this is the same Mac after a repair

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
| Nothing but four token counts per provider per day leaves the device | `DailyTokens` (its shape) |
| A provider's day is the sum of all its logins on this device; days without tokens aren't sent | `DailyTokens.summed`, which both the upload and the join form's preview use, so the preview is exactly what is sent |
| A device's private key never leaves it and is never logged | `SigningKeyStore` (Keychain, with the UserDefaults fallback Notify! uses for ad-hoc builds) |
| Uploading a day again replaces that device's row; it never adds, and never touches another device's | Server |
| A missed hour, or a device asleep for days, heals on the next upload | `LeaderboardUploader`: uploads from the day of `lastUpload` to today, at most 30 days, and on join, or once added, the last 30; a copy made its own device keeps the copied `lastUpload` |
| Uploads stay hourly by the clock, even after the Mac sleeps | `LeaderboardUploader.uploadDue()`: uploads only when there is no `lastUpload` or it is at least an hour old by the wall clock. The App driver only asks often (every 5 minutes and on wake) and never decides |
| An hourly upload that would send exactly what the last good one sent, from the same key on the same day, with no refused day waiting to be tried again, goes nowhere and still counts as up to date: the server already holds it. The first upload after launch, and an upload the person asked for, always go | `LeaderboardUploader.uploadDue()`, against the last upload it sent since launch |
| An upload you asked for always goes, hour or not | `LeaderboardUploader.uploadNow()`: Refresh in the popover, whatever tab is open, joining, and switching a shared provider |
| Every write and every private read is signed by one of the member's device keys | Server |
| Who you are comes from the device whose key verified the signature, found by `X-Key`; never from a parameter or a name | Server |
| A signed request is accepted once, and only within 5 minutes of its timestamp | Server |
| A username is unique ignoring case | Server |
| A username is 3–20 of `A–Z a–z 0–9 - _` | **Two owners, deliberately:** `Username` for instant feedback, the server as authority. Both check the same `vectors.json`, so they cannot drift silently |
| No future days, nothing older than 30 days, and no member's provider-day above the plausibility cap, summed over their devices. With devices each such day is refused alone, listed under `refused` in a `2xx`, and the rest of the upload is kept | Server |
| Standings rank by total tokens (the five counts summed); ties by username | Server |
| Each device's rows count in periods that end on that device's own date, the one it sent with its last upload, while it is within a day of UTC's | Server |
| A hidden member is absent from the public board and still sees their own standing | Server |
| Your own upload shows on the board you read at once, the same place *Your rank* says; everyone else's within two minutes | Server (an upload counts that member's standings again and drops the boards it changes from the edge cache) |
| A standing is counted when the days under it change, never when it is read: an upload, deleted days, or a new UTC day, which moves every period. Reading the board or *Your rank* costs the same however many members and days the board holds | Server (standings kept on write; [§5](#5--the-api) *Standings, counted when days change*) |
| The globe shows only countries, only for members who opted in; tokens only where at least three are | Server |
| A member who hasn't opted in sees the globe offered once, until they opt in or dismiss it | `LeaderboardMembership.showsGlobeHint` |
| A shared rank image shows one standing in one board view (rank, where that is, tokens, the provider mix) and no other member's name; there is none to share before a rank | `RankCard` |
| *Top N%* only in the top half, where N is the rank over every member, rounded up; *#r of N* below it; *Top 100* on a board longer than it lists; nothing when the rank isn't among the members listed | `RankCard.placement` |
| A profile link is a platform and a handle that fits its rules, never a URL | `ProfileLink` (the app, as you type) and the server (the authority); one `vectors.json` |
| Leaving deletes the member, every device and every row, on the server | Server — the app forgets the key only after a 2xx |
| A turned-off Leaderboard uploads nothing, joined or not, and keeps the membership as it was | `LeaderboardMembership.uploadCredentials` (nil while off) |
| Turned off stays off across launches, and outlives leaving and joining again | `LeaderboardMembership.isOn`, kept as `leaderboard.on` apart from the membership record |
| Turning it back on catches up the days missed, up to 30 | `LeaderboardUploader`'s range from `lastUpload`, unchanged; `Leaderboard.turnOn()` asks for it at once |
| While off there is no Leaderboard tab, and the popover falls back to its provider | The popover reads `membership.isOn` |
| A member has at most 5 devices that aren't removed | Server |
| A device is added only when another device of the member, past its first week, approves the code it shows, within 10 minutes, once; the new device names the member and asks before it uploads | Server, and the new device |
| For its first 7 days an added device changes and reads only its own days and settings, with the member's settings and standing: `/me` leaves out the other devices and their rows, and `/me/export` is refused; it can't rename or hide the member, change its globe or link, approve a device, remove another, delete a removed device's days, or leave. After that, and from the start for the device that joined, it may do what the member may | Server |
| Removing a device revokes its key at once and says which device removed it; its days stay and count until deleted; removing another device in its first week, the app offers *Remove and delete its days* beside *Remove*; the last device can't be removed | Server, and the app's dialog |
| Only a removed device's days can be deleted, by another device of the member past its first week, for one provider, one day or all | Server |
| Every device in use past its first week shows, once, each device added since it last read `/me`, with **Remove**; a device in its first week sees only itself | `LeaderboardMembership.devices` |
| A device whose key the server no longer knows forgets its membership | `LeaderboardUploader`, as for a member the server forgot |
| The member's name, visibility, globe and link come from the server; a device's copy follows every `/me` | `LeaderboardMembership` |
| A day the server refused is sent again with each upload until it is taken or 30 days old | `LeaderboardMembership.refused`, read by `LeaderboardUploader` |
| A key whose `machine` hash isn't this Mac's uploads nothing, and asks until answered: *Make this Mac its own device* or *Keep the key here* | `LeaderboardMembership.holdsCopiedKey` |
| A new device's label is filled in with the Mac's model, never its computer name | `DeviceLabel` |
| Every request names its client in `X-Client`, signed or not; the macOS app as `claudebar-macos/<version>` | `LeaderboardHTTPClient` |
| Until the board and your standing for the view you're looking at have come back, the tab says it is loading; it never says *0 tokens* or *No one is on the board* for an answer it doesn't have yet | The popover tab, from whether it holds an answer for its view |
| No rule lowers a member's number on a guess: two devices' rows always both count | Server |

## 5 · The API

Host: `https://claudebar-api.tddworks.com`; the public board page is `https://claudebar.tddworks.com/leaderboard`, which reads `/board` from its own origin. The server's code, storage and limits are private (`tddworks/claudebar-server`); this section is the contract the app relies on.

| Route | Auth | Does |
|---|---|---|
| `POST /join` `{username, publicKey, label}` | none, rate-limited per IP | creates the member and its first device: `201 {username}`; `409 usernameTaken` if the name is taken, `409 keyTaken` if the key is already a device's or waiting, `400 badLabel` for a label that isn't 1–40 characters without control characters. Without `label` (an app from before devices) the device is called "Mac" |
| `POST /devices` `{publicKey, label}` | none, rate-limited per IP | starts adding a device: answers `201 {code, expiresIn: 600, interval: 5}`, the code shown as `WDJB-MJHT` and read however it's typed (case, dash); `409 keyTaken`, `400 badLabel` as for `POST /join`. Until a device of the member approves the code, the key's signature only proves it holds the key: `GET /me` answers it `202` with no member data, and every other signed route refuses it |
| `GET /me/devices/pending/{code}` | signed, limited to 10 a minute per member with approving | what approving `code` would add: `{label, requestedAt}`; `404 unknownCode` when there's no such code, or it expired |
| `POST /me/devices` `{code}` | signed, limited to 10 a minute per member | approves the device that showed `code`: `201 {publicKey, label, addedAt}`; `404 unknownCode` for a code that's unknown, expired or used; `409 deviceLimit` when the member has 5 devices; `403 deviceTooNew` from a device in its first week |
| `DELETE /me/devices/{publicKey}` | signed | removes a device: its key is revoked, its days stay; `409 lastDevice` for the last device; `403 deviceTooNew` from a device in its first week removing another |
| `DELETE /me/devices/{publicKey}/days[?provider=][&day=]` | signed | deletes a removed device's days, for one provider, one day or all; `403 notYours` for a device in use, `403 deviceTooNew` from a device in its first week |
| `PUT /usage` `{today, days: [DailyTokens]}` | signed | upserts each of the signing device's days; `today` is the device's date, refused when more than a day from UTC's. With devices, a day that is too old, in the future, or would put the member over the cap is refused alone: the answer is `200 {stored, refused: [{provider, day, reason}]}`, `provider` and `day` echoed as sent, `null` for a row that wasn't an object |
| `GET /me` | signed | the member (`username`, `visible`, `shareCountry`, `country`, `link`), their standing in a view, their devices (`publicKey`, `label`, `addedAt`, `removedAt`, `removedBy`), and each device's rows that a period can still count (the last 31 days, all an upload ever sends), each with `device`, the public key of the device that sent it. `removedBy` is `{publicKey, label}` or `null`. From an added device in its first week, only its own device and rows, with the member and the standing. Signed by a key still waiting for approval: `202 {waiting: true, expiresIn}`; by one whose code expired: `401` |
| `GET /me/export` | signed | the same, with every row each device ever uploaded, as a downloadable JSON file; `403 deviceTooNew` from an added device in its first week |
| `PATCH /me` `{username?, visible?, shareCountry?, link?}` | signed | rename, hide or show; opt in to the globe (the server then keeps the country Cloudflare's edge reports for that request, and never updates it) or out (it forgets it at once); set the profile link as `{platform, handle}` (`x`, `instagram` or `github`, each with its own username rule, pinned by `vectors.json`) or remove it with `null`; `403 deviceTooNew` from a device in its first week |
| `DELETE /me` | signed | deletes the member, every device and every row; `403 deviceTooNew` from a device in its first week |
| `GET /globe?period=30d` | none | every country opted-in members share; members and tokens (`countries`) only where at least 3 are, the rest named without a number (`present`, A–Z) |
| `GET /board?period=7d&provider=claude` | none | standings of visible members, up to 100, a member's days summed over their devices, each in its own periods, cached at the edge for two minutes, dropped from the uploader's data centre by each `PUT /usage`; the app reads it without its local HTTP cache |

**Signing.** On join, or when it asks to be added, a device makes a `Curve25519.Signing.PrivateKey` (CryptoKit) and sends its public half. Every signed request carries:

```
X-Key:       <the device's public key, base64url, as sent on join>
X-Member:    <username>   (kept for servers before devices; ignored when X-Key is present)
X-Timestamp: <unix seconds>
X-Nonce:     <16 random bytes, base64url>
X-Signature: base64url( sign( METHOD \n PATH?QUERY \n TIMESTAMP \n NONCE \n hex(SHA256(body bytes)) ) )
```

Every request, signed or not (`POST /join` and `POST /devices` too), also carries `X-Client: <name>/<version>`: the macOS app `claudebar-macos/<version>`, ClaudeBar for Windows `claudebar-windows/<version>`. It isn't a credential and isn't signed; it lets the server tell clients apart and refuse one broken version alone, answered `426 clientRefused` on every route ([#507](https://github.com/tddworks/ClaudeBar/issues/507)). A request without it comes from a macOS app from before this rule.

**A removed device's key** is answered `401 {error: "unauthorized", message, removedBy: {publicKey, label}}` on every signed route, so an app from before devices forgets its membership as it does for a member the server forgot.

**Periods per device, in one query.** A board view joins each row to its device and keeps the rows inside that device's own period, v1's window ending on the device's date rather than one date, then sums per member as v1 does. The device's date is its `today` while that is within a day of UTC's, and UTC's date once it isn't, so a device that stopped uploading (removed, turned off, a wiped Mac) ages out of *Today* and *7 days* as v1's rows do. For a 7-day window, say: `end = CASE WHEN julianday(date('now')) - julianday(device.today) <= 1 THEN device.today ELSE date('now') END`, then `WHERE row.day BETWEEN date(end, '-6 days') AND end … GROUP BY member`. One member's week can span time zones that way and still be one `GROUP BY`; the indexes and the exact SQL are `claudebar-server`'s.

**Standings, counted when days change.** That `GROUP BY` runs when a standing can change, never on a read, and its sums are kept: a member's total per period and per provider, and over every provider. A standing can change only when:
- **a device uploads** (its rows and its `today` move): that member's standings are counted again, in the same transaction as the upload, from their own last 31 days, the only ones a period can hold;
- **a removed device's days are deleted**: that member's, the same way;
- **the UTC date turns**: a device whose `today` falls more than a day behind ends its periods on UTC's date from then on, and every period's first day moves. Every member's standings are counted again once a UTC day, by the first read or the hourly cron after midnight, whichever comes first.

`/me` carries only the rows a period can still count, so it too costs the same however long the member has uploaded; `/me/export` carries every row.

Hiding, suspending, renaming and leaving change who is shown, not a total, so the board applies them when it reads. A board read then looks up one view's top 100 in an index on the total; *Your rank* reads the member's own row and counts the members above it. Ties are by username, ignoring case, in byte order.

Counting on every read made a read cost every stored row, history included, so D1's rows read grew with members × members × days. With 64 members and under 2,000 rows it reached 75% of the free plan's 5M a day (2026-10-07).

The Worker verifies with WebCrypto's Ed25519 against the public key `X-Key` names, over **the exact bytes received**, never re-serialised JSON. The canonical string is pinned by `Tests/DomainTests/Leaderboard/vectors.json`, of which the server keeps an identical copy.

CryptoKit's Ed25519 signatures are randomised, so the shared vectors are **verified** on both sides, never compared byte for byte.

## 6 · Privacy

The second destination after Notify! that sends ClaudeBar's own state outward, so the same rules apply, stated plainly:

- **What leaves a device:** the username, and per shared provider per day four token counts. No cost, no model names, no projects, no paths, no prompts, no account email. Devices change none of this: the hash of a Mac's hardware UUID that spots a copied key stays on the device (§2a). To join or be added, a device also sends its public key and its label (below), and every request names the app and its version (`X-Client`, §5); none of these is usage, and none reaches the board.
- **What a device is called** is a label the person types when it joins or is added, filled in with the Mac's model ("MacBook Pro", "Mac mini"), which they can change. Never the computer's name, which is often a person's ("Jane's MacBook Pro"). The model comes from the `product-name` on the I/O Registry's device-tree `product` node on Apple silicon ("MacBook Pro (14-inch, 2021)"), with the parenthetical dropped. On an Intel Mac it comes from `IOPlatformExpertDevice`'s `model` ("MacBookPro16,1"), its family mapped to a name ("MacBook Pro"). When neither can be read, the label is "Mac". Only the member's own devices past their first week see it on `/me`, as they see each device's rows; the board shows only the sum.
- **Where it goes:** a Cloudflare Worker run by tddworks, and from there to a public page if visible.
- **Off by default.** Nothing is sent until the user joins, and only for providers they tick.
- **A profile link is optional, and only a handle.** A member may add one X, Instagram or GitHub handle; the address is always built from the platform's own base, never typed. It is not verified, and every place it shows says so.
- **The globe is opt-in, and only a country.** With *Show my country on the globe* on, the server keeps the two-letter country Cloudflare's edge sees the request that turned it on come from, once: later requests don't change it, or a VPN's exit would move the member from call to call; the Mac sends no location and asks for none. Never a city, coordinates or the IP. Publicly a country is named from its first member; its members and tokens are totalled only where at least three are, and the web board's tokens-on-the-globe figure adds up only those totals, never a number that, less the shown ones, would be one member's own. Turning it off forgets the country at once.
- **Leaving is deletion,** on the server, not hiding: the member, every device and every row. Removing one device only revokes its key; deleting its days is its own act, offered beside removing for a device in its first week.
- **The Worker logs no IP addresses and no request bodies.** Cloudflare itself still sees IPs to serve the request.

## 6a · Security, as the app sees it

Nothing the app relies on depends on the server's code staying secret, and the app holds no secret but its own key.

- **Only you can post as you.** Every write and private read is signed with an Ed25519 key made on one of your devices; the server holds only the public halves, which can check a signature but never make one. Who you are comes from the device whose key verified the signature, never from a parameter or a name.
- **A captured request can't be replayed.** The signature covers the method, path, query, time, a one-time nonce and the body's hash, and the server accepts it once, within five minutes.
- **Each key stays on its device.** It lives in the Keychain in release builds. A locally built, ad-hoc signed app can't use the Keychain, so the key falls back to UserDefaults, as Notify!'s token does. A whole-account copy (Migration Assistant, a restore) takes it along. On another Mac the copy finds that the hardware UUID isn't the one recorded with its key, uploads nothing, and asks whether to become its own device or keep the key, unless the copy was made before this rule (§2a). A stolen key of a device past its first week can do what you can: post, rename, approve a device, remove your others, delete a removed device's days, or leave. A v1 key could already post and leave.
- **Adding a device needs a device you have.** A code only starts the request; a device of the member past its first week approves it, after seeing the new device's label, within 10 minutes, once. Approving and reading codes are limited per member, asking per IP. Every other device past its first week then shows the new one with **Remove**, and for its first week the new device can change nothing but its own days and read no other device's: the phishing RFC 8628 §5.4 warns of, a stranger asking you to approve their code, ends in a device you see and remove before it can lock you out or read your devices' days.
- **Totals are self-reported.** A modified client, or logs written by hand, can inflate its own numbers. The server refuses a member's provider-day above the cap, summed over their devices, so devices and copied log folders don't multiply it, and no prizes ride on the board. Two devices counting the same logs both count, bounded by the cap; nothing is subtracted on a guess (§2a). Nothing on the client can prove a number is real.
- **The server may forget a member** who joined and never uploaded, or a device that was removed; the app then forgets the membership too, on its next upload, and shows the join form again (`LeaderboardUploader`).

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
| `LeaderboardMembership` | The laws of §4 on this device | Only ticked providers leave; only providers with usage history can be ticked; a provider's logins are summed; the member's settings follow `/me`; a key whose `machine` hash isn't this Mac's never uploads; refused days are tried again |
| `RequestSigner` | The canonical string, signed with CryptoKit Ed25519 | Pinned by `Tests/DomainTests/Leaderboard/vectors.json`; the server checks an identical copy |
| `LeaderboardUploader` + App driver | Uploads 30 days on join, then hourly from `lastUpload` with the refused days, and now when you ask; an hourly upload identical to the last one sent is skipped | `lastUpload` moves only on success, or on a skipped upload the server already holds. The driver asks `uploadDue()` every 5 minutes and on `NSWorkspace.didWakeNotification`; a `Timer`'s clock stops while the Mac sleeps, so the hour is the uploader's to judge |
| Server | The server's laws of §4 | Private repo `tddworks/claudebar-server`; deployed with the `cf` CLI |

| Piece | Home |
|---|---|
| `LeaderboardMembership`, `DailyTokens`, `Username`, `BoardView`, `Standing`, `RankCard`, `LeaderboardUploader` | `Sources/Domain/Leaderboard/` |
| `@Mockable` ports `LeaderboardAPI`, `SigningKeyStore` and `MachineIdentity` (this Mac's hardware UUID and model, faked in tests to stand for another Mac); plain `LeaderboardSettingsRepository` (like Notify!'s, now also keeping `refused`, the `machine` hash and the devices already shown) and `@MainActor` `TokenLogs`, faked in tests | `Sources/Domain/Leaderboard/` |
| `Device`, `DeviceCode`, `DeviceLabel` | `Sources/Domain/Leaderboard/` |
| `IOKitMachineIdentity`: `MachineIdentity` read through IOKit (`IOPlatformUUID`, the model) | `Sources/Infrastructure/` |
| `LeaderboardHTTPClient`, `CredentialSigningKeyStore`; settings as `leaderboard.*` in `JSONSettingsRepository` | `Sources/Infrastructure/` |
| `Leaderboard` (wiring, the 5-minute check and the wake observer, `refresh()` for the popover's Refresh, `share(_:)` for *Share my rank*, `turnOff()`/`turnOn()` and the one-time `offNotice`), `MonitorTokenLogs`, popover tab, `RankCardImage` (the image, in the member's theme) and `RankShareOverlay`, `TurnOffMenu` (the tab's *Turn off ▾*, drawn in the popover's top layer so the scroll view never clips it), `LeaderboardPane` (with its *Devices* list, *Add a device*, and the notices for a device added, a copied key and a refused day), the join form's *Already a member? Add this Mac* | `Sources/App/` |
| Server and board page | Private repo `tddworks/claudebar-server` |

## 8 · Build sequence

Test-first slices, each green on its own. Slices 1–11 and 16 are built: 11 and 16 on the server (`tddworks/claudebar-server` #1, and 16's PR). 12–15, §2a's devices in the app, are not built yet.

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
11. **Worker: devices** (in `tddworks/claudebar-server`). Pins: an existing member's key becomes their first device, holding every row; the device that joined, then or later, is never held to the first week, and an added one is for 7 days; `X-Key` finds the device and `X-Member` is ignored then; without `X-Key`, the member by `X-Member` and the device by the key that verifies; a pending key is answered `202`, an expired one `401`; a code works once, within 10 minutes, approved only by a device of the same member past its first week; a sixth device is refused (`409 deviceLimit`); an added device in its first week can't `PATCH /me`, approve, remove another, delete a removed device's days or leave (`403 deviceTooNew`); removing revokes at once, answers the removed key `401 unauthorized` with `removedBy`, and keeps the rows; the last device can't be removed (`409 lastDevice`); only a removed device's days can be deleted, by a device past its first week, for one provider, one day or all, and an in-use device's is `403 notYours`; the cap is checked on the member's sum; a day too old, in the future or over the cap is refused alone and listed under `refused` in a `2xx`, for clients with and without `X-Key`, replacing slice 4's `400` for a future day; each device's rows count in periods ending on its own `today` while that is within a day of UTC's, and on UTC's date once it isn't; `/me` carries `username`, the devices with `removedBy`, and each row's device, and to an added device in its first week only its own device and rows; `/me/export` refuses it (`403 deviceTooNew`).
12. **Signing with `X-Key` and `X-Client`, the member's settings from `/me`, and a refused day.** Pins: every signed request names the device's key; every request, signed or not, names the client (`claudebar-macos/<version>`); a rename on another device reaches this one's name on the next `/me` and never makes it forget its membership; visibility, globe and link follow `/me`; a day under `refused` is said, sent again with each upload until taken or 30 days old, and doesn't stop the other days; `lastUpload` moves as for a good upload.
13. **Adding and removing devices.** Pins: the label is the Mac's model from `MachineIdentity`, "Mac" when it can't be read, never its computer name; the new device waits, names the member it joined and asks before its first upload, then uploads 30 days; approve shows the label before it adds; every other device past its first week shows the new one once, with **Remove**, a device turned off shows it when turned on, and one in its own first week once that week ends; removing another device in its first week offers *Remove and delete its days* beside *Remove*, which removes and then deletes its days, and removing an older one or itself doesn't; removing this device forgets the key only after the server's 2xx; a removed device forgets its membership on its next upload's `401` and says which device removed it.
14. **A copied key.** Pins [§2a's copied-key rules](#a-key-copied-to-another-machine), with a faked `MachineIdentity`: a key whose `machine` hash isn't this Mac's uploads nothing and asks until answered; a key with no hash gets this Mac's; every key made on join, when added, or by *Make this Mac its own device* is recorded with this Mac's hash, so the next launch asks nothing, and leaving or being removed forgets the hash with the key; *Make this Mac its own device* gets a new key approved, forgets the copied key, its hash and the copied `refused` days, and uploads from the copied `lastUpload`'s day; *Keep the key here* records this Mac's hash and changes nothing else; the hash never leaves the device. Before it ships, an App Store-signed build on a real Mac reads `IOPlatformUUID` and the model in the sandbox (§9).
15. **Surfaces**, from a mockup in `design-concept/leaderboard/` first (AGENTS.md: a UI change starts there): the Settings pane's *Devices* list (in a device's first week, only *This Mac* and the day the week ends; after it, label, *This Mac*, added, removed and by which device, *Remove*, *Remove and delete its days* when removing another device in its first week, and *Delete its days* for a removed device), *Add a device* with the code and **Approve**, the join form's *Already a member? Add this Mac* with its code, a wait and the member's name to confirm, the notice that a device was added, the copied-key dialog, and the notice for a refused day. The copied-key dialog's *Keep the key here* says plainly that, while the other Mac is still in use, the two Macs will overwrite each other's days.

16. **Worker: standings counted when days change** (in `tddworks/claudebar-server`). Pins: the board, *Your rank* and the globe answer exactly what counting every row on each read answered, for members with several devices in different time zones, hidden, suspended and tied; an upload, and deleting a removed device's days, show at once; a device that stopped uploading ages out on the next UTC day without anyone uploading; a board read, *Your rank* and an upload each read a bounded number of rows however many days are stored.

Each user-visible slice adds its CHANGELOG line; the feature's `README.md` lands with slice 8.

## 9 · Open questions

- ~~**More than one Mac per username?**~~ Yes: several devices per member, each with its own key, added by a code another device approves ([§2a](#2a--devices-one-member-several-machines)). Asked in [#507](https://github.com/tddworks/ClaudeBar/issues/507).
- **Losing the key.** With a second device past its first week it's a device to remove and one to approve (§2a). With one, a reinstall or a lost Keychain item still locks a member out of their name: a recovery code shown once at join, or a manual reset by an admin?
- **A key that can't be copied.** Today the key migrates with the account (§2a), and the hardware UUID check answers that. A `ThisDeviceOnly` item in the data protection keychain wouldn't migrate ([Apple](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)). That keychain needs a provisioning profile ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)), which the Mac App Store build has and the Developer ID build doesn't. Worth a Developer ID profile, or is detection enough?
- **Same logs on two devices, a follow-up.** The devices core leaves days two devices read from the same logs counted twice, bounded by the cap (§2a). Each of these is a feature of its own, for after the core:
  - *A shared folder, before it counts twice:* when a provider is ticked, point out a log file iCloud Drive holds ([`isUbiquitousItem`](https://developer.apple.com/documentation/foundation/urlresourcevalues/isubiquitousitem)) or one under `~/Library/CloudStorage`, where File Provider keeps Dropbox, OneDrive and Google Drive. It misses `~/Dropbox` outside File Provider, Syncthing and rsync.
  - *The same day, twice:* name two devices' rows for one provider and day whose five counts are all equal. A hint, not proof: small repeated days can match by chance, and partial copies never match.
  - *Not counting days here:* let one device withhold such days, deleting its rows and never sending them again, until undone.
  - *Partial copies:* a keyed MinHash of record ids on each row would find partial overlaps, but only with a key the member's devices share and the server never sees; otherwise the server could test guessable ids, Mistral's session folders being named by time. The key would travel inside the add-a-device flow, encrypted to the new device.
- **Reading the Mac in the sandbox, and what changes its UUID.** The App Store build is sandboxed. Reading `IOPlatformUUID` and the model through IOKit is meant to work there; slices 13 and 14 fake `MachineIdentity`, so that is confirmed only by running an App Store-signed build on a real Mac. That a logic-board replacement changes the UUID stays an assumption, backed only by the UUID being read live from the hardware. If the UUID can't be read, that build keeps no hash and a copy goes unnoticed, as in v1; if the model can't, the label is "Mac" (§2a, §6).
- **The first week.** Seven days is a judgment call: long enough to see the *device added* notice on a machine used weekly, short enough not to stand in the way of someone setting up a new Mac. Shorter, longer, or a choice for the member?
- **Reviewing the board.** Nothing proves a number is real. Bounds and the maintainer's `suspended` are the defence, as on every self-reported board. Should the Worker queue members for review, as tokscale does? It flags a member's share of all tokens, a multiple of the median, and two accounts with near-equal totals. That's for `tddworks/claudebar-server`.
- **Web login.** v1 shows your data in the app and offers Export. A one-time link from the app to a short web session is designed in outline and deferred.
- **Spam and abuse.** Rate limit on `POST /join` per IP is designed. Cloudflare Turnstile, a username blocklist, and an admin hide are not yet decided.
- ~~**Where does the Worker's code live?**~~ In the private repo `tddworks/claudebar-server` (moved 2026-10-04 by the maintainer). The app and the server share `vectors.json`; change both copies together.
- ~~**Rank by what?**~~ Total tokens: input + output + cache write + cache read. Decided by the maintainer; output-only stays an option if cache-heavy totals feel unfair.
- ~~**Codex tokens?**~~ In v1: Codex gets a `usageHistory` read from its session logs, needing the generic `inputIncludesCacheRead` rule.
- ~~**What does "today" mean across time zones?**~~ Each device's own date: every upload carries the device's `today`, believable within a day of UTC's, and each device's rows count in periods ending on its own date. The board still answers in one query (§5).
- ~~**Mistral keeps only totals?**~~ `DailyTokens.unsplit` carries tokens a log doesn't split, so they still count.
- ~~**Where is the data stored?**~~ Cloudflare D1 behind a Worker. Settled because writes must pass server checks (a database the app writes to directly would need a secret in an open-source app), and D1's SQL answers a board view in one `GROUP BY`. Within the free tier only when that `GROUP BY` runs as days change, not on every read: [§5](#5--the-api) *Standings, counted when days change*.
- ~~**Can someone use a public key to act as another member?**~~ No. A public key only verifies; signing needs the private half, which never leaves its device.
