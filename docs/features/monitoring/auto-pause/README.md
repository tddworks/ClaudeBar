---
description: Let a product turn its own switch off when every login has run out, and back on at the next reset — you get a notification both times, and one click turns it back on. Use when you keep a product you don't need while it's empty.
---

# Auto-pause on empty

Some products sit empty for hours — a Claude plan spent by noon, a Codex pool waiting for the weekly reset. While it's empty, its pill, its alerts and its menu bar space are spent on a status that can't change until the reset. **Auto-pause on empty** (Settings → Providers → a product → *Turn off when empty*) lets that product turn its own switch off when every one of its logins has run out — and turn it back on when a refresh shows room again. You get a notification both times.

## Turn it on

**Settings → Providers → click a product → *Turn off when empty*.** Off by default, per product: ClaudeBar never turns anything off you didn't ask for, and turning the setting on does nothing until the product is actually empty.

## What happens

- When every counted login of the product is **depleted** (0%), ClaudeBar turns the product's switch off and says so once: *"<product> ran out"*, with a **Turn Back On** button.
- The row in Settings → Providers reads **Waiting for a reset**. While it waits, ClaudeBar quietly refreshes just that product in the background — about once a minute, the same pace as anywhere else.
- At the first refresh that shows room again, ClaudeBar turns the switch back on and says so once: *"<product> is back"*.

Paused logins don't count: if you paused a login yourself, it stays out of the judgement, as everywhere in ClaudeBar. A login with no data — not set up, or a fetch that failed — is never counted as empty either.

## Getting it back early

- **The notification's button** turns the product back on straight away.
- **Any turn of the switch** — in the popover, Settings, or `open "claudebar://enable?provider=claude"` ([URL schemes](../../app/url-schemes/README.md)) — does the same. The product stays off in exactly one case: *you* turned it off.

Turning the product back on while it's still empty doesn't get it paused again behind your back: it stays on until it has recovered and emptied again.

**Turning the setting off** un-arms the feature: the marker is cleared and, if ClaudeBar was the one holding the product off, the product goes back on. A product you turned off yourself stays off.

## Gotchas

- **Waiting costs a refresh a minute.** An off product isn't in the app's normal rotation, so the waiting loop refreshes it itself — one product, background pace. That is the whole cost.
- **The reset is observed, not predicted.** ClaudeBar doesn't guess from a reset time; it waits for a refresh that shows room. A failing API delays the turn-back-on.
- **A relaunch doesn't forget.** The waiting state survives quitting and reopening ClaudeBar; a stale marker is cleaned up quietly.
- Auto-pause news is a notification on this Mac. Webhooks hear quota and status alerts, not this.

## See also

- [Multiple accounts](../../providers/multi-account/README.md), for pause and the product switch
- [Settings](../../../settings.md), where the keys live
- [Design](design.md), for contributors
