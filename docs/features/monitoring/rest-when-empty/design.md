---
description: Contributor design for Rest when empty — the per-product opt-in that dims a product while every one of its logins is depleted, without touching its switch, and tells the person when it rests and when it is back. Read before touching RestWhenEmpty, WhenEmpty, the product status read, or the claudebar://show-anyway link.
---

# Rest when empty: design

User guide: [README.md](README.md). Mockup: [design-concept/rest-when-empty](../../../../design-concept/rest-when-empty/index.html).

**Status: BUILT.** The opt-in card (Settings → Providers), the saved `WhenEmpty`, the dimmed pill, page and menu-bar readout, the two notices, and the `claudebar://show-anyway` link.

| For | Read |
|---|---|
| The product switch, pause, two facts | [multiple accounts](../../../features/providers/multi-account/design.md) |
| `claudebar://` routing | [URL schemes](../../../features/app/url-schemes/README.md) |
| The notice's shape | [In use](../../../features/in-use/design.md), the same port-and-announcer pattern |

## The one sentence

**A product whose every counted login is out rests: it stays where it is, dimmed and labelled *RESTING*, until a refresh shows room again. Its switch is never touched.**

Rest is a look, not a switch. `Provider.isEnabled` stays the person's alone ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-each-one-one-owner)): a resting product is still in the lineup, so the Monitor's own loop keeps refreshing it and sees the reset. Nothing else watches. Rest is a **follower** of refreshes, like In use and the alerts (*what follows a refresh is never the Monitor's*). The one Monitor piece is a read, `status(of product:)`, which `overallStatus` and `selectedTabStatus` read too.

```
 Settings card · popover page · notification button       (render and tell, decide nothing)
        │ restWhenEmpty.turn(_, product:) · showAnyway(product) · claudebar://show-anyway
        ▼
 RestWhenEmpty (Domain) ── review(login) on every onRefreshed
        │   state(of: product) ─▶ WhenEmpty.after(monitor.status(of: product), now:) ─▶ saved
        ▼
 RestWhenEmptyRepository (port) ← JSONSettingsRepository: providers.<id>.restWhenEmpty
 RestWhenEmptyAnnouncer  (port) ← RestNotifications (Infrastructure; the link is the App's)
```

## What the code says, the findings this stands on

1. **The switch is the person's, and a second writer breaks it.** The first shape turned `isEnabled` off itself and rebuilt whose off it was from three more facts (a marker, the instruction, an in-memory set). Settings' product switch calls `monitor.setProductEnabled` directly, so those facts drifted, and a relaunch lost the in-memory half. So rest never writes the switch.
2. **A product in the lineup is refreshed by the Monitor.** The background loop refreshes the lineup; a resting product is in it. The reset is seen by the same refresh as any other number, so rest needs no loop, no clock and no sweep of its own.
3. **Per-product emptiness is one read.** `QuotaMonitor.status(of product:)` is the healthiest unpaused login's status under the person's policy, `nil` while no unpaused login has usage. A product is empty when that read is `.depleted`. It works the same for one Claude login and for a Codex pool.
4. **Balances recover only by observation.** `resetsAt` is optional and not uniform across providers, so a reset is never inferred from a timestamp. It counts when a refresh shows room. A failed fetch (no usage) never counts either way: not empty, not recovered.

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Rest when empty** | the card's switch, per product: the person asks for the product to rest while empty. Off until turned on | the product's own switch (`isEnabled`), which only the person flips |
| **empty** | the product's status is `.depleted`: every *counted* login is out, and at least one has usage | one login running low; *no data* (a fetch that failed is not empty) |
| **counted** | unpaused logins that have usage | paused logins (out of every judgement, as ever) |
| **resting** | asked, and seen empty: dimmed, labelled *RESTING*, since a moment it remembers | *PAUSED* (a login the person stopped watching); off (the person's switch) |
| **shown anyway** | the person clicked *Show anyway* while it rested: drawn as usual until it has room again | turning the card off (which forgets the whole thing) |
| **watching** | asked, and not empty, or back from empty | a product nobody asked to rest (no saved value) |

## 2 · The aggregate

```
WhenEmpty  ◇  (Domain/Monitoring, a value)          the one saved fact per asked product
├── .watching                                       not empty: drawn as usual
├── .resting(since: Date)                           empty: dimmed, labelled, since then
├── .shownAnyway                                    empty, but the person asked to see it
├── after(_ status: QuotaStatus?, now:) -> WhenEmpty   the transition, pure
└── isResting                                       what a view may render

RestWhenEmpty  ◆  (Domain/Monitoring)              one per app, follows the Monitor
├── isOn(product) · turn(_, product:)               the card's switch: nil ↔ .watching
├── state(of: product) -> WhenEmpty?                nil: never asked
├── isResting(product)                              the pill, the page, the menu bar, the row
├── showAnyway(product)                             the page's and the notice's button
├── follow(monitor)                                 onRefreshed → review (the composition root, once)
├── review(login)                                   state.after(monitor.status(of: product)) → save, tell
├── RestWhenEmptyRepository (port) ← JSONSettingsRepository
└── RestWhenEmptyAnnouncer  (port) ← RestNotifications (Infrastructure)

QuotaMonitor.status(of product:) -> QuotaStatus?    min over the unpaused logins' statuses
                                                    under the policy; nil when none has usage.
                                                    overallStatus and selectedTabStatus read it

RestNotice · resting | back · productName · providerId           plain values, no link
claudebar://show-anyway?provider=<id>               URLSchemeAction: builds the link and parses it
```

The transition, every case:

| Now | status `.depleted` | status `nil` (nothing seen) | status with room |
|---|---|---|---|
| `.watching` | `.resting(since: now)` | `.watching` | `.watching` |
| `.resting(since:)` | unchanged | unchanged | `.watching` |
| `.shownAnyway` | `.shownAnyway` | `.shownAnyway` | `.watching` |

Saved under `providers.<id>.restWhenEmpty` in `~/.claudebar/settings.json` ([docs/settings.md](../../../settings.md)), one value per product. Absent means the person never asked, or turned the card off.

| Saved | Reads as |
|---|---|
| absent | not asked: the card is off, nothing rests |
| `{"state": "watching"}` | `.watching` |
| `{"state": "resting", "since": 1761220000}` | `.resting(since:)`, seconds since 1970 |
| `{"state": "shownAnyway"}` | `.shownAnyway` |

## 3 · What a resting product quiets

| Surface | Resting | Owner of the look |
|---|---|---|
| Popover pill | stays, dimmed | `MenuContentView`, from `isResting` |
| Popover page | the *RESTING* line with *since 2:14 PM* and *Show anyway* on top, the cards dimmed below | `MenuContentView`, words from `RestText` |
| Menu-bar readout | stays, dimmed; the tooltip adds *resting* | `StatusItemLabelDriver`, from `isResting` |
| Settings → Providers row | *Resting until the reset* | `ProvidersPane`, words from `RestText` |
| The product's switch, refreshes, statuses, alerts | untouched | nothing to own: rest is a look |

## 4 · The tells

```swift
restWhenEmpty.isOn(product)                  // the card's switch (bound through turn)
restWhenEmpty.isResting(product)             // the pill, the page, the readout, the row
restWhenEmpty.state(of: product)             // the page's *since*
restWhenEmpty.showAnyway(product)            // the button, and claudebar://show-anyway
restWhenEmpty.follow(monitor)                // the composition root, once
URLSchemeAction.showAnywayLink(provider: id) // the notice's button
```

Views never read settings.json and never compare statuses: they render `isResting` and tell `showAnyway` and `turn`.

## 5 · Invariants, each law with one owner

| Law | Owner |
|---|---|
| A product rests only where the person asked: per product, off until turned on, and turning it on does nothing until a refresh sees it empty | `RestWhenEmpty.turn` |
| The product's switch is the person's alone: rest never writes `isEnabled`, and the switch never writes the rest | `Provider.isEnabled` (nothing in rest touches it) |
| Empty is seen, never assumed: a login with no usage (not set up, fetch failed) is not counted, and paused logins are out | `QuotaMonitor.status(of product:)` |
| A product reads its healthiest counted login (min): it is empty only when every counted login is, and the popover, the menu-bar icon and rest read it the same | `QuotaMonitor.status(of product:)` |
| Where a product is now is one saved value, so a relaunch keeps it: watching, resting since a moment, or shown anyway | `WhenEmpty` (saved by `RestWhenEmptyRepository`) |
| One rest per emptying: while empty stays empty nothing changes, and a product shown anyway is not rested again until it has had room | `WhenEmpty.after` |
| Recovery is observed, never inferred: a refresh must show room. A failed fetch neither recovers nor empties | `WhenEmpty.after` |
| A resting product is dimmed and labelled, never hidden: its pill, its page and its readout stay | the App, from `isResting` |
| The person is told when it rests and when it is back from resting, never for *Show anyway* or the card's switch | `RestWhenEmpty.review` → `RestWhenEmptyAnnouncer` |
| The `claudebar://show-anyway` link has one owner, which builds it and parses it | `URLSchemeAction` |
| What follows a refresh is never the Monitor's | `QuotaMonitor.onRefreshed` |

## 6 · Open questions

- **Webhooks**: rest news is a notification on this Mac only. A webhook kind can follow later, the way the recap did.
- **Quieting alerts and the menu-bar icon's colour**: today a resting product still counts in `overallStatus` and its status alert has already fired at the crossing. Leaving it out would teach the Monitor about rest; deferred until someone asks.
- **`Accounts.status`** (policy-blind, `.healthy` when nothing has usage) is a fourth copy of the healthiest-login rule. Folding it into `status(of product:)` is CANONICAL §8's unification, not this feature's edit.
