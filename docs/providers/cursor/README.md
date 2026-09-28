---
description: Track Cursor's monthly included usage, Auto and API when reported, on-demand spend and enterprise team credits, read with the sign-in the Cursor app already stores. Use when setting up Cursor or when it shows nothing, EMPTY or "Session expired".
---

# Cursor

Shows your Cursor plan's included usage for the current billing month as separate Monthly, Auto and API cards when the usage API reports those fields, plus on-demand usage and team credits (Enterprise) when they're turned on, and your plan (Free, Pro, Business, Ultra, Enterprise). Everything resets at the end of Cursor's billing cycle. Auto is Cursor's Auto mode, Composer, and Agent-driven IDE operations.

## Setup

1. Install [Cursor](https://cursor.com) and sign in to it. ClaudeBar reuses that sign-in; there is nothing to configure.
2. Settings → Providers → Cursor: turn it on (it is on by default).

## Gotchas

- **Nothing shows at all** means Cursor's local state database isn't at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. ClaudeBar skips Cursor silently until that file exists, so install Cursor and open it once.
- **"Authentication required. Please log in."** means the database has no sign-in token (you're signed out of Cursor) or cursor.com returned 403. Sign in to Cursor again.
- **"Session expired. Re-authenticate in Cursor settings."** means cursor.com rejected the stored token (HTTP 401). Sign out and back in to Cursor, then refresh ClaudeBar.
- **The numbers are Cursor's own figures, shown as separate cards.** Monthly is `totalPercentUsed` (the same "You've used X%" figure Cursor shows). Auto and API are `autoPercentUsed` and `apiPercentUsed` when the API sends them. ClaudeBar does not derive one from the others. Bonus credits count toward Monthly capacity. Before ClaudeBar 0.4.73, paid plans with bonus credits could show EMPTY.
- **The menu bar still defaults to Monthly.** To see the combined total and the API figure at the same time, keep Quota on Monthly and set Secondary Quota to API under Settings → [Menu Bar](../../features/menu-bar/README.md).
- **On-demand and team cards only appear when that usage is enabled and has a limit.** Uncapped on-demand spend doesn't get a card.
- **"No usage data found in Cursor response"** means the account reported no plan usage, on-demand limit, team credits or unlimited flag. Some free accounts look like this.

## See also

[design.md](design.md) · [troubleshooting](../../troubleshooting.md)
