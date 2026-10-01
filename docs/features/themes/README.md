---
description: Pick a built-in theme (System, Light, Dark, CLI, Christmas) or import an iTerm2 .itermcolors scheme to match your terminal. Use when changing how the popover, menu bar and Settings look.
---

# Themes

A theme sets the look of the popover, the menu bar label and the Settings window: backgrounds, text, accents, fonts and the default status colors.

## Quick start

Settings → **Appearance** → **Theme**, then click one. The change applies straight away.

## Built-in themes

| Theme | Look |
|---|---|
| **System** (default) | Follows macOS appearance: Light in light mode, Dark in dark mode |
| **Light** | Light variant of the glass look |
| **Dark** | Purple-pink glassmorphism |
| **CLI** | Monochrome terminal look with a monospaced font and green accents |
| **Christmas** | Festive colors, snowfall, and a snowflake menu bar icon |

**Christmas turns itself on** from December 24 to 26, but only if you've never picked a theme yourself. After the 26th it switches back to System. Once you've chosen any theme, ClaudeBar leaves your choice alone.

## Import a terminal theme

Match ClaudeBar to your terminal with any iTerm2 color scheme:

1. Get a `.itermcolors` file. You can export one from iTerm2 (Settings → Profiles → Colors → Color Presets… → Export), or download one of the 450+ schemes at [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes/tree/master/schemes).
2. Settings → **Appearance** → **Import Theme**, and pick the file.
3. The theme appears in the grid under the scheme's name. Click it to use it.

- Imported themes are saved in `~/.claudebar/themes/` (one JSON file each) and come back after a restart.
- To remove one, click the × on its tile. Built-in themes can't be removed.
- ClaudeBar keeps the parsed colors, not the file, and rebuilds the theme from them at every launch. So imported themes pick up improvements to the color mapping in later versions.

## Gotchas

- Only `.itermcolors` is supported. Other formats (Alacritty, Kitty, Windows Terminal) need converting first.
- An import fails with "Import failed: …" when the file isn't a property list, or is missing the background, the foreground, or any of the 16 ANSI colors.
- Importing a scheme with the same name as an earlier import replaces it.
- A theme only sets the *default* status colors. Custom status colors and High Contrast sit on top of every theme, imported ones included. See [status colors](../status-colors/README.md).

## See also

[Status colors](../status-colors/README.md) · [menu bar](../menu-bar/README.md) · [THEME_DESIGN.md](../../architecture/THEME_DESIGN.md) for contributors adding a theme
