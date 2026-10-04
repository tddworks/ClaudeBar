---
description: Kiro as data — kiro-cli given /usage on stdin, the usage mapping, its windows, and added accounts in their own home folders. Use when changing how Kiro is read.
---

# Kiro: design

Kiro is `Modules/Providers/Resources/Providers/kiro.json` and `kiro-usage.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it.

## Source

A `command`: `kiro-cli` over pipes, given `/usage\n/quit\n` on stdin, with a 30-second timeout. ANSI colour codes are stripped before reading. A missing CLI is `cli.missing` → *CLI not found: kiro-cli*.

## Mapping

- `Bonus credits: X/Y …, expires in N days` → a **Bonus credits** quota, Y−X of Y left, resetting N days from now. It is a grant that expires, not a window that refills, so it states **no window length** (the old probe called it weekly and gave it 7 days).
- `Credits (X of Y covered in plan)` with `resets on MM/DD` → a **Monthly** quota. The reset date has no year: a date already past this year is next year's. Its window is **the month that ends on that date**, measured in the Mac's own calendar, rather than the old 30-day guess. With no reset date it states no window.
- Neither line → *No quota data found in Kiro CLI output*.

## Accounts

An added account is a **home folder** someone signed in to with `kiro-cli` (a `path` setting, `mustExist`). Its `accounts.patch` runs the same command with `HOME`, `KIRO_HOME` and the XDG folders pointing into that folder, and with `KIRO_API_KEY` unset. `requiresFiles` makes a folder that has since gone *Key needed* rather than letting `kiro-cli` start a sign-in of its own (#216).

- **Folders are never shared.** `Provider` refuses a folder another login already uses.
- **Re-sign-in.** The Accounts card asks the person to sign in again in that folder.
- **Removal.** Removing the account leaves the folder where it is.
- **Default login.** The default login uses the real home, so its Settings form has nothing to show.
