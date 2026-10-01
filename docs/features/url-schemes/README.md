---
description: Drive ClaudeBar from Raycast, Alfred, Shortcuts, BetterTouchTool or a terminal with claudebar://open, claudebar://refresh and claudebar://settings. Use when scripting ClaudeBar.
---

# URL Schemes

ClaudeBar registers the `claudebar://` URL scheme, so anything that can open a URL can trigger it.

| URL | Does | From a terminal |
|---|---|---|
| `claudebar://open` | Opens the popover and brings ClaudeBar to the front | `open claudebar://open` |
| `claudebar://refresh` | Refreshes every enabled provider now | `open claudebar://refresh` |
| `claudebar://settings` | Opens the Settings window | `open claudebar://settings` |

There are no other actions and no parameters. Anything else, such as `claudebar://foo`, `claudebar://open/` or `claudebar://refresh?now=1`, is ignored and logged as "Received unhandled URL" in the [log](../../troubleshooting.md).

## Examples

- **Raycast / Alfred**: add a quicklink or web search pointing at `claudebar://refresh`.
- **Shortcuts**: an *Open URLs* action with `claudebar://open`.
- **BetterTouchTool / MTMR**: set a widget's tap action to `claudebar://open`. The [Touch Bar](../touch-bar/README.md) guide has full widget configs.
- **Shell or cron**: `open claudebar://refresh`.

## Gotchas

- `claudebar://open` only opens the popover. It doesn't toggle it, so running it again while the popover is open doesn't close it.
- ClaudeBar must be installed where macOS can find it (normally `/Applications`). If the URL opens nothing, launch ClaudeBar once by hand so macOS registers the scheme.
- The action can also be given as a path: `claudebar:///refresh` works the same as `claudebar://refresh`.
- `refresh` is a full refresh, the same as opening the popover: it covers every enabled provider, not only the menu bar ones, and includes the daily usage cards.

## See also

[Touch Bar](../touch-bar/README.md) · [menu bar](../menu-bar/README.md) · [troubleshooting](../../troubleshooting.md)
