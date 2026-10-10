# All providers — design

> Applies [the design](../../architecture/ARCHITECTURE.md) to the popover's
> **All** page. Users: [README.md](README.md). Mockup:
> [design-concept/all-providers](../../../design-concept/all-providers/index.html).
> **Status: built** (as-built screenshots in the mockup's `as-built/`).
> It reads the lineup the Monitor already keeps; nothing in the canonical tree
> changes, and the Monitor is not edited for it.

## The person and the moment

Someone who pays for several assistants opens the popover between tasks to
learn one thing: *which of them can I keep working with?* Today that is a
click per pill, or the **Overview Mode** switch, which turns the popover into
one long list of every provider's full page. **All** answers it in one view:
a small card per provider with the quota that runs out first. A tap opens that
provider's page as before.

## The words

| Word | Means |
|---|---|
| **All** | the pill, and the page it opens: a card per provider in the lineup |
| **page** | what the popover shows under the pills: *All*, *Leaderboard*, or one provider |
| **card** | one provider on *All*: its badge, its **tightest** quota as a ring, the next quota, a tap target |
| **tightest** | the quota with the least left (`UsageSnapshot.lowestQuota`); with several logins, the tightest of their tightest |
| **Open on** | where the popover lands each time it opens: *Where I left it* (default) or *All* |

## The pill row

```
 [▦ All] [🏆 Leaderboard] ┃ [Claude] [Codex] [Gemini] …
  └── pages about everything ─┘   └── one provider each ──┘
```

All leads, Leaderboard follows it, a divider, then a pill per product. All
shows only with two or more products; Leaderboard only while it is on (as
today). The divider shows when either of them does.

## Pieces

| Piece | Where | One job |
|---|---|---|
| `PopoverPage` | `Sources/Domain/Monitor/PopoverPage.swift` | the page under the pills: `.all`, `.leaderboard`, `.provider`. Replaces `MenuContentView`'s `showsLeaderboard` flag, so a third page is a case, not a second flag. The provider itself stays `monitor.selectedProviderId` |
| `Overview` | `Sources/Domain/Monitor/Overview.swift` | built from the tabs and the Monitor's usage: `isOffered` (two or more products), `cards` in pill order, the header's `badge`, and the `critical` / `warning` / `healthy` counts |
| `OverviewCard` | same file | one product: `tab`, `badge` (`ProviderBadgeState` of its logins), `tightest` and `next` quota, `tightestLogin` when there are several, `loginCount` |
| `PopoverOpensOn` | `Sources/Domain/Settings/PopoverOpensOn.swift` | `.whereILeftIt` / `.all`, and the page an open lands on |
| `AppSettingsRepository.popoverOpensOn()` / `setPopoverOpensOn(_:)` | Domain port, `JSONSettingsRepository` | keeps it at `app.popoverOpensOn`; unset with the old `app.overviewModeEnabled` on reads `.all` |
| `AppSettings.popoverOpensOn` | `Sources/App/Settings/AppSettings.swift` | the observed setting; replaces `overviewModeEnabled` |
| Pill row, *All* page, header | `MenuContentView`, `OverviewCardView` | render `Overview` and `PopoverPage`: never count, compare or pick a quota |
| *Open on* row | `GeneralPane` | replaces the *Overview Mode* switch |

```
 QuotaMonitor ── tabs, usage(of:), status(of:) ──▶ Overview(monitor) ──▶ All page (cards)
                                                        │                   │ tap
 AppSettings.popoverOpensOn ──open──▶ PopoverPage ◀─────┴───────────────────┘
                                         │            (.provider + selectedProviderId)
                                         ▼
                                   MenuContentView: pills · header · page
```

## Laws

| Law | Owner |
|---|---|
| All is offered only with two or more products in the lineup; with fewer, the page falls back to the provider | `Overview.isOffered` |
| cards follow the pill order; they never re-sort as quotas change | `Overview.cards` |
| a card's ring is its tightest quota; with several logins, the tightest login's, named | `OverviewCard` |
| a product with no numbers still gets a card, saying *Unavailable*, *Not set up* or *Syncing* like the header (#259) | `OverviewCard.badge` |
| the header's badge on All is the worst card's; the counts are of cards with numbers | `Overview` |
| tapping a card opens that product on its first login | `MenuContentView` → `PopoverPage.provider` |
| each open lands where *Open on* says; *Where I left it* keeps the page, as the popover does today | `PopoverOpensOn` |
| someone who had Overview Mode on opens on All after the update | `JSONSettingsRepository` (compatibility read) |
| ⌘0 opens All; ⌘1–⌘9 stay the products | `MenuContentView` keyboard shortcuts |
| the menu bar keeps showing the selected provider; All does not change it | unchanged |

## What goes

- **Overview Mode** (`app.overviewModeEnabled`, the long list of full
  sections): All replaces it. The key is only read once, as above.
- Cost, today's usage and the 30-day chart stay on each provider's page;
  All answers *can I keep working?*, not *what did I spend?*.

## Tests

- Domain: `OverviewTests` — offered with two products, not one; cards in pill
  order; tightest quota and the next; tightest login across several; a card
  without numbers says why; counts and header badge.
- Domain: `PopoverOpensOnTests` — an open lands on All, or keeps the page.
- Infrastructure: `JSONSettingsRepositoryAppTests` — `.whereILeftIt` when unset,
  round-trips, and the old Overview Mode on reads `.all`.
