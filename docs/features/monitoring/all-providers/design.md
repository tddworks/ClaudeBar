# All providers — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to the popover's
> **All** page. Users: [README.md](README.md). Mockups:
> [design-concept/all-providers](../../../../design-concept/all-providers/index.html)
> (the cards), [design-concept/all-page-bars](../../../../design-concept/all-page-bars/index.html)
> (**Bars**, the second style).
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

A second question rides along, and the cards cannot answer it: *how much room do
I have on each window, lined up beside the others?* A card answers **one**
question per provider — its tightest quota — so a provider with three or more
quotas is silently cut to two, and two rings compare different windows (a
session against a weekly). **Bars** is the same page asked the second question:
one full-width row per provider, a line per quota the person watches, every bar
starting and ending at the same place so two providers' sessions can be read
against each other. It is a *style* of the page, chosen in Settings, not a
second page and not a mode of the popover.

## The words

| Word | Means |
|---|---|
| **All** | the pill, and the page it opens: a card per provider in the lineup |
| **page** | what the popover shows under the pills: *All*, *Leaderboard*, or one provider |
| **card** | one provider on *All*: its badge, its **tightest** quota as a ring, the next quota, a tap target |
| **tightest** | the quota with the least left (`UsageSnapshot.lowestQuota`); with several logins, the healthiest login's — the one the product's status reads |
| **Open on** | where the popover lands each time it opens: *Where I left it* (default) or *All* |
| **All page style** | how a provider reads on *All*: *Rings* (default, the cards) or *Bars* |
| **row** | one provider on *All* in **Bars**: a header and one **line** per watched quota |
| **line** | one quota in a row: its label, its **bar**, its percentage, its reset |

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
| `PopoverPage` | `Sources/Domain/Monitoring/PopoverPage.swift` | the page under the pills: `.all`, `.leaderboard`, `.provider`. Replaces `MenuContentView`'s `showsLeaderboard` flag, so a third page is a case, not a second flag. The provider itself stays `monitor.selectedProviderId` |
| `Overview` | `Sources/Domain/Monitoring/Overview.swift` | built from the tabs and the Monitor's usage: `isOffered` (two or more products), `cards` in pill order, the header's `badge` and `status` (the worst card's, `nil` while none has numbers), the `critical` / `warning` / `healthy` counts, and `tightestCard` (the card whose ring runs out first). The [local API](../../alerting/local-api/design.md) answers from it too |
| `OverviewCard` | same file | one product: `tab`, `badge` (`ProviderBadgeState` of its logins), `login` (the one the card reads), `tightest` and `next` quota, `tightestLogin` when there are several, `loginCount`; the product's `best` and `inUse` logins, as `Accounts.best` and `InUse` answer; each login's `source` and `usageHistory` |
| `PopoverOpensOn` | `Sources/Domain/App/PopoverOpensOn.swift` | `.whereILeftIt` / `.all`, and the page an open lands on |
| `AppSettingsRepository.popoverOpensOn()` / `setPopoverOpensOn(_:)` | Domain port, `JSONSettingsRepository` | keeps it at `app.popoverOpensOn`; unset with the old `app.overviewModeEnabled` on reads `.all` |
| `AppSettings.popoverOpensOn` | `Sources/App/Settings/AppSettings.swift` | the observed setting; replaces `overviewModeEnabled` |
| Pill row, *All* page, header | `MenuContentView`, `OverviewCardView` | render `Overview` and `PopoverPage`: never count, compare or pick a quota |
| *Open on* row | `GeneralPane` | replaces the *Overview Mode* switch |
| `OverviewCard.lines` | same file as `OverviewCard` | every quota of the login the card already reads, in window order — what **Bars** draws. An extension of `tightestOf`, not a second way to choose a login |
| `AllPageStyle` | `Sources/Domain/App/AllPageStyle.swift` | `.rings` (default) or `.bars`. The page's own choice of how to print, like `PopoverOpensOn` — never a flag on `OverviewCard` |
| `AppSettingsRepository.allPageStyle()` / `setAllPageStyle(_:)` | Domain port, `JSONSettingsRepository` | keeps it at `app.allPageStyle`; unset reads `.rings` |
| `AppSettings.allPageStyle` | `Sources/App/Settings/AppSettings.swift` | the observed setting; writes through on change |
| `QuotaCardBar` | `Sources/App/Views/QuotaProgressBar.swift` | a quota's bar with its pace tick under it — the one piece `WrappedStatCard`, a **Bars** line and `QuotaCardView` all draw. Its fill follows the status, its tick the pace; a bar's ends land where the row puts them, so every bar on a page starts and ends at the same x |
| `QuotaLineText` | `Sources/App/Views/QuotaCardText.swift` | the words a quota line prints — its title (login first when needed) and its number (a percentage, or a balance's amount). One copy for the ring card's rows and **Bars**' lines |
| `OverviewBarsPageView` | `Sources/App/Views/OverviewCardView.swift` | the *Bars* page: a row per card, a `QuotaBar` per line — renders `lines` and never sorts or filters |
| *All page style* row | `GeneralPane`, beside *Open On* | picks the style |

```
 QuotaMonitor ── tabs, usage(of:), status(of:) ──▶ Overview(monitor) ──▶ All page (cards or rows)
                                                        │                   │ tap
 AppSettings.popoverOpensOn ──open──▶ PopoverPage ◀─────┴───────────────────┤
 AppSettings.allPageStyle ──style──▶ .rings ? OverviewPageView : OverviewBarsPageView
```

## Laws

| Law | Owner |
|---|---|
| All is offered only with two or more products in the lineup; with fewer, the page falls back to the provider | `Overview.isOffered` |
| cards follow the pill order; they never re-sort as quotas change | `Overview.cards` |
| a card's ring is its tightest quota; with several logins, the healthiest login's, named — a product's logins are interchangeable ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | `OverviewCard` |
| a product with no numbers still gets a card, saying *Unavailable*, *Not set up* or *Syncing* like the header (#259) | `OverviewCard.badge` |
| the header's badge on All is the worst card's; the counts are of cards with numbers | `Overview` |
| tapping a card opens that product on its first login | `MenuContentView` → `PopoverPage.provider` |
| each open lands where *Open on* says; *Where I left it* keeps the page, as the popover does today | `PopoverOpensOn` |
| someone who had Overview Mode on opens on All after the update | `JSONSettingsRepository` (compatibility read) |
| ⌘0 opens All; ⌘1–⌘9 stay the products | `MenuContentView` keyboard shortcuts |
| the menu bar keeps showing the selected provider; All does not change it | unchanged |
| the style is the page's: it chooses how a provider is printed and nothing else — the login a card reads, the numbers, the status and the badge are the same either way | `AllPageStyle` |
| unset means Rings, so nobody's All page changes after updating | `JSONSettingsRepository` |
| in **Bars**, each row prints the card it sits under: the row sits where the pill order put the card (`Overview.cards`), and it reads the same login the card reads | `OverviewCard.lines` |
| lines are ordered by their **stated** window, shortest first, so like sits beside like across rows; a quota whose window the provider never stated sorts last, tightest first. Never a window guessed from a name ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | `OverviewCard.lines` |
| a provider with no numbers still gets a row, saying *Unavailable*, *Not set up* or *Syncing*, and still opens its page | `OverviewCard.badge` |
| a tap opens that provider's page in either style; **Bars** never replaces the ring cards, it is one more way to ask | `MenuContentView` → `PopoverPage.provider` |

## What goes

- **Overview Mode** (`app.overviewModeEnabled`, the long list of full
  sections): All replaces it. The key is only read once, as above.
- Cost, today's usage and the 30-day chart stay on each provider's page;
  All answers *can I keep working?*, not *what did I spend?*. **Bars** does
  not bring Overview Mode back either: it prints the quotas, not the pages.

## Tests

- Domain: `OverviewTests` — offered with two products, not one; cards in pill
  order; tightest quota and the next; the best login across several; a card
  without numbers says why; counts and header badge.
- Domain: `OverviewCardLinesTests` — every quota the card reads, not just the
  tightest two; lines by their stated window, shortest first; a quota with no
  stated window last, tightest first; the same login the ring reads; nothing
  for a provider with no numbers. (Hidden quotas are the Monitor's law, kept
  in `QuotaMonitorHiddenQuotasTests`.)
- Domain: `PopoverOpensOnTests` — an open lands on All, or keeps the page.
- Infrastructure: `JSONSettingsRepositoryAppTests` — `.whereILeftIt` when unset,
  round-trips, and the old Overview Mode on reads `.all`; `.rings` when unset,
  and `allPageStyle` round-trips.
- App: `QuotaLineTextTests` — the words a line prints: the quota's title, the
  login first when several need telling apart, a percentage in the display
  mode, a balance as its amount.
