---
description: Show live quota gauges on a MacBook Pro Touch Bar in every app, or feed BetterTouchTool, MTMR and scripts from ~/.claudebar/status.json. Use on Touch Bar Macs or when wiring quota into another tool.
---

# Touch Bar

ClaudeBar draws a strip of quota gauges on the Touch Bar that stays visible in every app and full-screen Space. It needs no third-party tools and no Accessibility permission. The same switch also writes `~/.claudebar/status.json`, which BetterTouchTool, MTMR, SwiftBar or your own scripts can read.

Works on MacBook Pro models with a Touch Bar (13-inch M1/M2 and the Intel models).

## Quick start

1. **Settings → General → Touch Bar**. It's on by default.
2. Pick what it shows in **Settings → Menu Bar**. The Touch Bar uses the same providers (up to three) and, for each one, the same primary and secondary quota.
3. On the Mac: **System Settings → Keyboard → Touch Bar Settings…** → set **Touch Bar shows** to **App Controls** or **Expanded Control Strip**.

## What it shows

One cell per quota, centred on the bar, with a thin divider between cells. Each cell has:

- the provider's icon, or an SF Symbol when there's no icon for it
- the name, plus the quota's short label when a provider shows two quotas (`Claude 7d`). With two Antigravity quotas, each cell is labelled with the model pool.
- a reset countdown (`2:15`, `35m`, `3d`), shown only when the cell is wide enough
- a bold percentage and a progress bar. `—` means the provider hasn't returned data yet.

The percentage follows the display mode chosen at the top of **Settings → Menu Bar**. The colour follows that quota's own status: blue while healthy, amber for warning, and red with a `!` when critical or depleted. With the burn-rate warning on, the status is pace-aware. A provider showing two gauges can therefore show two colours, while its entry in `status.json` carries the provider's overall status. See [Status colors](../status-colors/README.md) for the cutoffs.

Tap anywhere on the gauges to open the ClaudeBar popover.

### While the popover or Settings is open

Any app can put its own buttons on the Touch Bar while its window is in front. While ClaudeBar's popover or Settings window is in front, you get:

- a badge with the selected provider, its lowest quota and a status dot
- a scrolling row of enabled providers. Tap one to select it.
- **Refresh** (the same as `⌘R`), which also shows a brief 🔄 on the gauges
- **Settings**

## Use it from other tools

With the Touch Bar switch on, ClaudeBar rewrites `~/.claudebar/status.json` every time the state changes, such as a refresh finishing or a different provider being selected. It doesn't poll. The file is replaced in one step, so a reader never sees half a file.

```json
{
  "enabled": true,
  "updatedAt": "2026-09-04T06:30:00Z",
  "menuBarText": "Claude: 42%",
  "status": "healthy",
  "selectedProviderId": "claude",
  "selectedProviderName": "Claude",
  "providers": [
    { "id": "claude", "name": "Claude", "status": "healthy",
      "percentUsed": 42.0, "percentRemaining": 58.0,
      "resetsAt": "2026-09-04T08:45:00Z", "resetText": "Resets in 2h 15m" }
  ]
}
```

- `status` is `healthy`, `warning`, `critical` or `depleted`. The top-level `status` is `unknown` before the first refresh, and `disabled` when the switch is off.
- `providers` lists every enabled provider, using each one's first quota. `percent*`, `resetsAt` and `resetText` are left out when the provider has no value for them.
- With the switch off, the file has `"enabled": false` and an empty `providers` list.

### Helper script

[`scripts/touchbar_status.py`](../../../scripts/touchbar_status.py) reads that file and formats it. It's in the source repository, so clone the repo to use it.

| Flag | Output |
|---|---|
| `--btt` (default) | BetterTouchTool JSON: text, background colour, icon |
| `--mtmr` | Text with a status emoji |
| `--text` | Plain text (SwiftBar, xbar, tmux) |
| `--json` | The raw file |
| `--icon [id]` | Path of a provider's PNG icon, if one exists |
| `--refresh` / `--open` / `--settings` | Opens the matching `claudebar://` URL |

For `--btt` icons, put your own PNGs at `~/.claudebar/icons/<provider-id>.png`, or at `scripts/icons/<provider-id>.png` next to the script. ClaudeBar ships none, so without them the script uses an emoji.

### BetterTouchTool

1. **Touch Bar** → **All Apps** → **+** → **Shell Script / Task Widget**.
2. Script: `python3 /path/to/ClaudeBar/scripts/touchbar_status.py --btt`, run every 10 seconds.
3. **Script Output Type**: **JSON (text, background_color, font_color)**.
4. Action: **Open URL** → `claudebar://open` (or `claudebar://refresh`).

### MTMR

Add this to `~/Library/Application Support/MTMR/items.json`. MTMR reloads on save.

```json
{
  "type": "shellStream",
  "width": 140,
  "bordered": true,
  "align": "right",
  "refreshInterval": 10,
  "commandPath": "/usr/bin/python3",
  "shellArguments": ["/path/to/ClaudeBar/scripts/touchbar_status.py", "--mtmr"],
  "actions": [{ "trigger": "singleTap", "action": "openUrl", "url": "claudebar://open" }]
}
```

The widgets' tap actions use ClaudeBar's URL schemes (`claudebar://open`, `claudebar://refresh`, `claudebar://settings`); see [URL schemes](../url-schemes/README.md).

## Gotchas

- **Turning the Touch Bar off also stops `status.json`.** BetterTouchTool, MTMR and scripts then read `"enabled": false`, and the helper script's BTT widget hides itself. Keep the switch on even on a Mac without a Touch Bar if something reads the file.
- **Nothing on the bar.** The gauges hide when no Menu Bar provider is available. Check **Settings → Menu Bar** and the macOS **Touch Bar shows** setting. If another app has taken over the Touch Bar, quit and reopen ClaudeBar.
- **Private API.** The always-on bar uses undocumented macOS calls, so a macOS update could break it. The popover's buttons and `status.json` don't depend on those calls.
- **"ClaudeBar: Offline" in a helper widget** means `~/.claudebar/status.json` is missing or unreadable. Make sure ClaudeBar is running, then run `python3 scripts/touchbar_status.py --text` in a terminal to see what it reads.

## See also

- [design.md](design.md): how the always-on bar is presented, and why it uses private API
- [URL schemes](../url-schemes/README.md)
