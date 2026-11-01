---
description: Kiro as data — the v3 engine's _kiro/account/getUsage over kiro-cli acp, falling back to kiro-cli given /usage on stdin, the usage mapping, its windows, and added accounts in their own home folders. Use when changing how Kiro is read.
---

# Kiro: design

Kiro is `Modules/Providers/Resources/Providers/kiro.json` and `kiro-usage.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it.

## Source

Two data sources, both read by `kiro-usage.js`:

- **`rpc` (default).** A `jsonRpc` fetch: `kiro-cli acp --agent-engine v3`, `initialize`, then `_kiro/account/getUsage`, with a 45-second timeout (the engine takes about 10 seconds to start). It is the request the v3 TUI's own `/usage` screen makes, so it depends on no screen text. Since kiro-cli made the v3 engine its default, `/usage` piped into plain `kiro-cli` reaches the agent as a chat message and prints no usage.
- **`cli` (fallback).** A `command`: `kiro-cli` over pipes, given `/usage\n/quit\n` on stdin, with a 30-second timeout, for a kiro-cli whose `acp` has no v3 engine or no such method. ANSI colour codes are stripped before reading.

A missing CLI is `cli.missing` → *CLI not found: kiro-cli*.

## Mapping

From `rpc` (`result.data`):

- each `bonusCredits` entry `{name, used, total, daysUntilExpiry}` → a **Bonus credits** quota, as below. With more than one grant, each is **Bonus credits: `name`** (or **Bonus credits `N`**, its place in the list, when the name is missing or shared), so each grant keeps its own card and can be hidden alone.
- each `usageBreakdowns` entry with `hasLimit` and a `limit` above zero → a quota, `limit − used` of `limit` left. The `Credits` breakdown is **Monthly**; any other keeps its `displayName`. Its reset date is `billingCycleReset` (`YYYY-MM-DD`).

From `cli`:

- `Bonus credits: X/Y …, expires in N days` → a **Bonus credits** quota, Y−X of Y left, resetting N days from now. It is a grant that expires, not a window that refills, so it states **no window length** (the old probe called it weekly and gave it 7 days).
- `Credits (X of Y covered in plan)` with `resets on MM/DD` or `resets on YYYY-MM-DD` → a **Monthly** quota. Without a year, a date already past this year is next year's; a full date is taken as it is.

A Monthly window is **the month that ends on the reset date**, measured in the Mac's own calendar, rather than the old 30-day guess. When the previous month is shorter than the reset day (a reset on March 31), it starts on that month's last day. With no reset date it states no window. No quota from either → *No quota data found in Kiro CLI output*; from `rpc` that hands off to `cli`.

## Accounts

An added account is a **home folder** someone signed in to with `kiro-cli` (a `path` setting, `mustExist`). `accounts.cli` runs the same command with `HOME`, `KIRO_HOME` and the XDG folders pointing into that folder, and with `KIRO_API_KEY` unset (#577). A folder that has since gone is *Key needed* rather than letting `kiro-cli` start a sign-in of its own (#216): a folder an account was given must still be there.

- **Folders are never shared.** `Provider` refuses a folder another login already uses.
- **Re-sign-in.** The Accounts card asks the person to sign in again in that folder.
- **Removal.** Removing the account leaves the folder where it is.
- **Default login.** The default login uses the real home, so its Settings form has nothing to show.
