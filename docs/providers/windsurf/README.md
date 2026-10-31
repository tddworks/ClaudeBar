---
description: Track Windsurf's daily and weekly quota, or its message and flow-action allowances, from the plan Devin Desktop (formerly Windsurf) saves locally. Use when setting up Windsurf or Devin Desktop or when its numbers look old.
---

# Windsurf

Shows how much of your Windsurf daily and weekly quota is left and when each resets, with your plan. On plans without those quotas it shows your message and flow-action allowances for the billing period.

## Setup

1. Open Devin Desktop (Windsurf's new name since June 2026) or the Windsurf app, and sign in once.
2. Settings → Providers → Windsurf: turn it on. It's **off by default**. There's no key to paste.

ClaudeBar reads the plan the app saves in its app-data folder, read-only: `~/Library/Application Support/Devin/User/globalStorage/state.vscdb` (Devin Desktop) or `~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb` (Windsurf) on macOS, `%APPDATA%\Devin\…` or `%APPDATA%\Windsurf\…` on Windows (or `~/AppData/Roaming` if `APPDATA` is empty or unset). When both are there, it reads the one changed last, so after Devin Desktop's **Migrate from Windsurf** the old copy is ignored. It runs nothing and sends nothing anywhere.

## Gotchas

- **The numbers only change while Windsurf runs.** Windsurf updates its saved plan itself; with Windsurf closed, ClaudeBar shows the last numbers it saved.
- **"Windsurf's saved plan is out of date. Open Windsurf to update it."** The saved plan's billing period has ended, so its numbers are old. Open Windsurf.
- **"Open Windsurf and sign in …"** Windsurf hasn't saved a plan yet. Until Windsurf has run once on this Mac, the card shows as not set up.
- **A free plan** shows its message pool when it saves one (Devin Desktop's free plan: messages left of the total, with no reset); a plan with nothing to measure shows no data.
- **Windows path support does not yet supply SQLite or mapping scripts.** Until those connections are implemented, the source reports *Unavailable*; it does not try a Mac command.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
