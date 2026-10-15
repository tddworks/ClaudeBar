---
description: Let a login whose weekly or monthly quota is spent step out of the way until the window refills, instead of holding its whole product at DEPLETED. Use when one account of several is empty and drags the rest down.
---

# Rest when spent

With more than one account on a provider, one spent login keeps the whole product at **DEPLETED** — the menu bar, the badge, the alerts — for as long as its window runs, even when your other accounts are fine.

**Rest When Spent** lets that login rest: it stops being fetched and stops setting its product's status, the page shows it under **RESTING** with the time its window ends, and it comes back on its own when the quota refills.

## Turn it on

Right-click a login in the popover (its chip, its card's header, or its row) and tick **Rest When Spent**. The first tick turns the policy on for that provider; tick it per login you want it on.

## What a resting login does

- **No refresh, no status, no alert, no menu-bar entry** — the same quiet as Pause.
- **Still on the page**, under **RESTING**, with its last numbers and *until when*.
- **Back on its own** when the window ends: the next refresh judges it afresh.
- Pausing it still works, and Pause wins while both hold.

## Wake a login sooner

Right-click the resting row and choose **Wake Now** — or untick **Rest When Spent**. The rest ends at once, and that login is never rested again until you tick it back.

## Gotchas

- **Nothing rests until the quota can say when it refills.** A provider that reports 0% without a reset time is never rested — ClaudeBar won't park a login it can't wake.
- **Spent means empty** — 0%. There is no threshold to tune; the built-in percentages already warn you before.
- **The longest window decides.** On Claude, Codex and Z.ai that is the weekly; a spent 5-hour session alone never rests a login.
- **Quotas you hid are left out** of the judgement, the same as for alerts.
- Resting never moves your terminal sessions; [Switch when low](../in-use/README.md) does that, and now skips resting logins.

## For contributors

The design, laws and storage keys: [design.md](design.md).
