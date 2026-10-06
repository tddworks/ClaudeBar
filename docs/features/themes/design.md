# Themes — design

> Applies [the design](../../architecture/ARCHITECTURE.md) to how ClaudeBar
> looks. Users: [README.md](README.md). The code is the reference for every
> property: `Sources/App/Theme/AppThemeProvider.swift`.

## The shape

- **A theme is a value**, one type implementing `AppThemeProvider`: its colours,
  gradients, corner radii, fonts and default status colours. It registers once
  in `ThemeRegistry.registerBuiltInThemes()`; nothing else lists themes.
- **Views ask the theme, never which theme.** A view reads
  `@Environment(\.appTheme)` and uses its properties — card backgrounds are
  `theme.cardGradient` and `theme.glassBorder`. A view that checks for the CLI
  or Christmas theme is the old system and is replaced, not extended.
- **A new property gets a default** in the protocol extension (`cardBorderWidth`
  is `1`, `cardShadow` is none), so adding one never edits every theme.
- **Shared colours live in `BaseTheme`**; a theme takes them by name instead of
  repeating the values.
- **What a theme says and draws is the theme's too**, never a branch on its id:
  the header's line under ClaudeBar (`tagline`), a status badge's words
  (`statusWord(for:)` — Platformer's HURRY UP! and GAME OVER) and their font
  (`badgeFont(size:)`), how a quota's bar
  is drawn (`progressStyle`: `.bar`, or `.blocks(10)` for Platformer), and how
  large a wide display font prints (`displayFontScale`), whether controls are
  round or square (`controlCornerRadius`, drawn through `controlShape`), the
  floor the action bar stands on (`groundHeight`), what heads the popover
  (`headerStyle`: `.scoreLine` puts a `ScoreLine` above the name and a ?
  block that refreshes in place of the status pill), which badges blink
  (`blinks(_:)`), the text on an accent fill (`textOnAccent`), a badge's
  corners (`badgeCornerRadius`) and the rivets in a card's corners
  (`cardRivetSize`, drawn by `.themeRivets()` on every popover card). A wrapper such as
  `StatusColorOverridingTheme` forwards every one, or the person's own status
  colours would quietly drop them.
- **An outlined theme** (`cardBorderWidth` above 1: Pop, Platformer) prints
  paper cards, inked pills and outlined big numbers — percentages and money
  alike (#499), and badges as round as its pills (`pillCornerRadius`). A
  bundled font is registered through `BundledFont`.
- **A theme's text style is the person's choice**: a theme that names one
  (`textStyleName`, Platformer's "Pixel") is resolved `styled(.themed)` or
  `styled(.classic)` from `AppSettings.themeTextStyle` (`app.themeTextStyle`
  in settings.json). Classic drops every face the theme bundles
  (`customFontName`, `displayFontName`, its badge face) and keeps the rest of
  the look. Settings shows the choice only for such a theme.
- **Views set text through `theme.font(size:weight:)`**, never
  `.system(…, design: theme.fontDesign)`, so a theme with `customFontName`
  (Platformer's Pixelify Sans) reaches every word; without one it is the
  same system font.

## The runner

A theme may put a runner on its floor (`runner`, `nil` by default; only
Platformer has one). It lives in its own lane above the floor, which the
action bar stands on, so the popover grows by `runner.laneHeight`. Nobody
plays it: it shows the selected provider's status and nothing else. Mockup:
[living-level.html](../../../design-concept/platformer-theme/living-level.html).

| Law | Owner |
|---|---|
| Which status it shows | `QuotaMonitor.selectedProviderStatus`, unchanged: the one the menu bar shows |
| How it moves for a status: strolls, walks, runs (and sweats), or falls in a pit | the theme: `runner.pace(for:)`, beside `statusWord(for:)` |
| Where it is, which way it faces, turning at the edges, the jump, the fall and the new runner after a reset | `RunnerLevel`, told the time, the pace and the lane's width |
| It jumps and a coin pops when a refresh finishes | the view tells `RunnerLevel.celebrate(at:)` when the ? block's `isSyncing` turns false; no new Monitor event |
| Reduce motion: it stands still, a coin still shows, the fall skips to GAME OVER | `RunnerLevel`, told `reduceMotion` by the view |
| No frames while the popover is closed | the view: its `TimelineView` pauses off screen |

It never takes input (`allowsHitTesting(false)`), makes no sound and never
appears in the menu bar. It is original pixel art, like the ? block.

**The runner is the person's choice**, like the text style: a theme with a
runner is resolved `walking(true)` or `walking(false)` from
`AppSettings.themeRunnerShown` (`app.themeRunner` in settings.json, on by
default). Off, the theme has no `runner`, so the lane goes and the popover is
its old height; the rest of the level stays. Views never read the setting.
Settings shows the switch only for a theme with a runner.

## Imported terminal themes

An `.itermcolors` file becomes a theme in four steps, each its own piece:

| Step | Rule | Piece |
|---|---|---|
| parse | 16 ANSI colours plus background and foreground, or the import fails | `ITermColorsParser` → `TerminalColorScheme` |
| map | red → critical, green → healthy, yellow → warning, cyan and blue → the accents; cards and glass are derived from the background; text tiers from the foreground | `TerminalThemeGenerator` |
| keep | the parsed colours, not the file, as JSON in `~/.claudebar/themes/` | `ImportedThemeStore` |
| load | regenerated and registered at every launch, so a better mapping reaches old imports | `ThemeRegistry` |

Another terminal format is one more parser that produces a
`TerminalColorScheme`; the mapping and the theme don't change.

Status colours a person chooses sit on top of every theme:
[status colors design](../status-colors/design.md).
