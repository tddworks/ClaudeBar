---
description: Replace the "ClaudeBar" title at the top of the popover with a name of your own, such as your team's or your own. Use when renaming the popover header or putting it back.
---

# Popover Title

The popover's header says **ClaudeBar** above *AI Usage Monitor*. You can put your own name there instead, such as `Acme AI Desk` or `Ren's Quotas`.

## Quick start

1. Settings → **Appearance** → **Popover Title**.
2. Type a name. The popover header changes as you type.
3. Clear the field, or click **Reset**, to go back to **ClaudeBar**.

## What it changes

- Only the big title in the popover header. The tagline under it, the logo, the status pill and every theme's look stay as they are.
- The name keeps the theme's title font, so it reads like the header always has.
- **ClaudeBar** stays in the app's own places: the About pane, the Settings sidebar, the menu bar's accessibility label and the Touch Bar.

## Rules

| You type | The header shows |
|---|---|
| nothing, or only spaces | **ClaudeBar** |
| `  Acme AI Desk  ` | `Acme AI Desk` (spaces around it dropped) |
| more than 24 characters | the first 24 |
| a line break | one line: breaks become spaces |

The name is stored as `app.popoverTitle` in `~/.claudebar/settings.json` ([settings](../../settings.md)).
