---
description: Contributor design for Auto-pause on empty — the per-product opt-in that turns a product's switch off when every one of its logins is depleted, watches quietly for the reset, turns it back on, and tells the person both times. Read before touching AutoPause, the product status read, or the claudebar://enable link.
---

# Auto-pause on empty: design

User guide: [README.md](README.md).

**Status: BUILT.** The opt-in card (Settings → Providers), the crossing, the quiet watching, the recovery, the two notices, and the `claudebar://enable` link.

| For | Read |
|---|---|
| The product switch, pause, two facts | [multiple accounts](../../../features/providers/multi-account/design.md) |
| `claudebar://` routing | [URL schemes](../../../features/app/url-schemes/README.md) |
| The notice's shape | [In use](../../../features/in-use/design.md) — same port-and-announcer pattern |

## The one sentence

**A product whose every counted login is out turns its own switch off — once — and turns it back on when a refresh shows room again, telling the person both times.**

Auto-pause is not a capability a definition declares and not a new Monitor loop: it is a **follower** of refreshes, exactly like In use and the alerts ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-each-one-one-owner): *what follows a refresh is never the Monitor's*). The one new Monitor piece is a read — `status(of product:)` — the product-level twin of `status(of login:)`.

```
 Settings card · row · notification button      (render and tell — decide nothing)
        │ autoPause.turn(_, product:) / turnBackOn(product:) · claudebar://enable
        ▼
 AutoPause (Domain) ── review(login) on every onRefreshed ──▶ pause · recover · un-arm
        │                                                        │
        │ sweep(product): monitor.refresh(providerIds:, kind: .background)
        │ (the quiet loop — the app loop never refreshes an off product)
        ▼
 QuotaMonitor.status(of product:) → QuotaStatus?   depleted only as seen
        ▲
 AutoPauseAnnouncer (port) ← AutoPauseNotifications (Infrastructure)
```

## What the code says today — the findings this stands on

1. **The product switch is the right lever, and nothing needs new plumbing to honour it.** `isEnabled` is read by `Providers.lineup` (the pills, the menu bar, refreshes, alerts), `QuotaMonitor.products` (every status and alert), `ProductTab.tabs` (the popover), `ProviderListOrder` and the settings sidebar (the lists). A product turned off leaves every surface at once; no consumer reads deeper than the lineup.
2. **Per-login depletion is knowable.** Each `Account` holds its own snapshot; `QuotaMonitor.status(of login:)` already answers one login's status under the person's policy, `nil` with no usage. A product is empty when at least one counted login has usage and every counted login reads `.depleted` — a definition that works the same for Mia's one Claude login and for a Codex pool.
3. **The refresh gap is real, and the existing path already crosses it.** The background loop refreshes the selected provider or a supplied set; the driver feeds it the lineup — so an off product is never refreshed by the app. But `Provider.refresh` refuses only *paused* logins — the product's switch is a different fact, and a login is still fetched while its product is off ([multiple accounts](../../../features/providers/multi-account/design.md)) — and `monitor.refresh(providerIds:kind:)` reaches any login and fires `onRefreshed`. Recovery can therefore be *observed*; the watcher only needs its own quiet loop to keep the promise.
4. **Balances recover only by observation.** A snapshot's `resetsAt` is optional and not uniform across providers, so a reset is never inferred from a timestamp. It counts when a refresh shows room again — and a failed fetch (no usage) never counts either way: not empty, not recovered.

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **empty** | every *counted* login's status is `.depleted`, and at least one has usage | a single login running low; *no data* (a fetch that failed is not empty) |
| **counted** | unpaused logins that have usage — the ones the product's status already reads | paused logins (out of every judgement, as ever) |
| **the marker** | `providers.<id>.autoPaused` in settings.json — *ClaudeBar* turned this product off | the switch itself (`isEnabled`), which both the person and ClaudeBar flip |
| **waiting** | ClaudeBar turned the product off, the instruction is on, and it watches for the reset | a paused login (nothing watches those); a disabled product with no marker (the person's own off) |
| **the crossing** | the refresh at which an on product is first seen empty | every later refresh that still sees it empty |
| **the quiet loop** | the per-product Task that refreshes a watched product in the background until the reset | the app's monitoring loop (which never refreshes an off product) |

## 2 · The aggregate

```
AutoPause  ◆  (Domain/Monitoring)          one per app, follows the Monitor
├── isOn(product) · turn(_, product:)      the standing instruction — off until turned on
├── isWaiting(product)                     the row's *Waiting for a reset*
├── turnBackOn(product)                    the notice's button, one click
├── follow(monitor)                        onRefreshed + adopt + start the quiet loops (production)
├── adopt()                                re-reads markers at launch — state only, no tasks
├── review(refreshed)                      the crossing, the recovery, the un-arming
├── sweep(product)                         one quiet tick: refresh the watched product
├── wasDepleted  ◇                         once-per-crossing memory, per product, in memory
└── AutoPauseAnnouncer (port) ← AutoPauseNotifications (Infrastructure)

QuotaMonitor.status(of product:) -> QuotaStatus?    min over the unpaused logins'
                                                    statuses under the policy; nil when
                                                    none of them has usage

AutoPauseNotice · turnedOff | turnedOn · productName · providerId · link
claudebar://enable?provider=<id>                    URLSchemeAction.enable(provider:)
```

Settings keys — the same `ProviderSettingsRepository` every provider reads, under `providers.<id>.*` in `~/.claudebar/settings.json` ([docs/settings.md](../../../settings.md)):

| Key | Holds |
|---|---|
| `autoPause` | the standing instruction. `false` until the person turns it on |
| `autoPaused` | the marker: ClaudeBar's own off, so watching survives a relaunch and the person's off is never touched |

## 3 · The tells

```swift
autoPause.isOn(product)                        // the card's switch (bound through turn)
autoPause.isWaiting(product)                   // the row: *Waiting for a reset*
monitor.onRefreshed { await autoPause.review($0) }   // the composition root wires it
autoPause.follow(monitor)                      // …and starts the quiet loops
URLSchemeAction(url:) == .enable(provider: id) // claudebar://enable
```

Views never read settings.json, never compare statuses and never watch: the card binds `turn`, the row renders `isWaiting`.

## 4 · Invariants — each law, one owner

| Law | Owner |
|---|---|
| A product turns itself off only where the person asked it to: the instruction is per product, off until turned on, and arming alone does nothing until a crossing | `AutoPause.turn` |
| Empty is seen, never assumed: at least one counted login has usage, every counted login reads `.depleted`; a login with no usage — not set up, fetch failed — is not counted, and never reads as empty | `QuotaMonitor.status(of product:)` |
| Paused logins are out of every judgement, as ever | `QuotaMonitor.status(of product:)` (reads unpaused only) |
| A product's logins are interchangeable: it is as empty as its emptiest counted login | `QuotaMonitor.status(of product:)` |
| ClaudeBar's off is the marker's, not the switch's: only a product off *with* the marker is waiting | `AutoPause` (the `autoPaused` key) |
| The person's own off is never touched — an off product without the marker stays off, however empty it is | `AutoPause.review` |
| One pause per crossing: while empty stays empty nothing fires again, and a manual re-enable is never re-paused until the product has recovered and emptied again | `AutoPause` (`wasDepleted`) |
| Recovery is observed, never inferred: a refresh must show room — a status at all, and not `.depleted`; a failed fetch neither recovers nor empties | `AutoPause.review` |
| While waiting, the watched product is refreshed — the quiet loop keeps the promise the app loop cannot, at the same cadence the Monitor clamps for the background | `AutoPause.sweep` · `QuotaMonitor.effectiveInterval` |
| Un-arming reverts ClaudeBar's own action, silently: withdrawing the instruction, or one click on *Turn Back On*, puts the product back on — the person's own off is left off | `AutoPause.turn` · `AutoPause.turnBackOn` |
| The person is told both times — turned off, turned back on — and never for a stale marker cleaned up quietly | `AutoPauseAnnouncer` ← `AutoPauseNotifications` |
| What follows a refresh is never the Monitor's | `QuotaMonitor.onRefreshed` |
| `claudebar://enable` takes exactly `provider`, once; anything else is not an action | `URLSchemeAction` |

Changed by this feature: *a product is off only when the person turns it off* (CANONICAL §5) now carries a standing-instruction clause — a product may turn its own switch off where the person left that instruction, visibly, one click to undo. The switch is still the person's in every other case.

## 5 · The review, step by step

```
review(login):
  product = monitor.product(of: login)
  status  = monitor.status(of: product)

  enabled branch:
    marker set?                → the person turned it back on: clean the marker, stop watching, silently
    status != .depleted?       → not empty (or nothing seen): clear the crossing memory, done
    instruction on ∧ not seen empty? → THE CROSSING: mark, flip off, announce, start the quiet loop
    otherwise                  → still empty since the last crossing: quiet

  off branch (marker set — ClaudeBar's off; the person's off never reaches here):
    instruction withdrawn?     → clean the marker, leave off, stop watching, silently
    status nil ∨ .depleted?    → still empty, or nothing seen yet: keep waiting
    otherwise                  → THE RESET: clean the marker, flip on, announce, stop watching
```

The quiet loop is one Task per watched product: sweep (refresh its logins, `.background`), sleep `effectiveInterval(requested: 60s, floors: [product.backgroundRefreshFloor])`, repeat while waiting. The loop exits on recovery, un-arming, or cancellation; `review` does the deciding through the same `onRefreshed` observers every other follower uses.

## 6 · Open questions

- **Webhooks**: the kinds a webhook carries are quota and status alerts; auto-pause news is action news, like In use's, and today reaches this Mac's notification centre only. A webhook kind can follow the same pattern later — deferred, not designed out.
- **Sleep until the reset**: when every counted login reports `resetsAt`, the loop could wake then instead of polling. Deferred: `resetsAt` is optional and not uniform, and one quiet refresh a minute is what the background already costs anywhere else.
- **A richer row badge** (e.g. a spinner on *Waiting for a reset*): the row's text is enough for now; `isWaiting` is the one fact a view may render.
- **`accounts.status(under:)`**: `Accounts.status` (policy-blind, `.healthy` when nothing has usage) and the new `status(of product:)` (policy-aware, `nil` when nothing has usage) share one idea. Folding them is the §8 unification — not this feature's edit.
