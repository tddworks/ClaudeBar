---
description: Let a product rest while every login has run out — it stays in the popover and the menu bar, dimmed and labelled RESTING, until a refresh shows room again. Its switch stays yours. Use when an empty product keeps taking your attention.
---

# Rest when empty

Some products sit empty for hours: a Claude plan spent by noon, a Codex pool waiting for the weekly reset. While it's empty, its pill and its menu-bar readout keep showing a status that can't change until the reset. **Rest when empty** (Settings → Providers → a product → *Rest when empty*) dims that product while every one of its logins has run out, and brings it back when a refresh shows room again. You get a notification both times.

## Turn it on

**Settings → Providers → click a product → *Rest when empty*.** Off by default, per product. Turning it on does nothing until the product is actually empty.

## What happens

- When every counted login of the product is **depleted** (0%), the product **rests**: its pill and its menu-bar readout are dimmed, and its page starts with **RESTING** · *since 2:14 PM* and a **Show anyway** button. You get one notification, *"<product> is resting"*, with the same button.
- The row in Settings → Providers reads **Resting until the reset**.
- ClaudeBar keeps refreshing it as usual. At the first refresh that shows room again, it stops resting and you get *"<product> is back"*.

The product's own switch is never touched. A product you turned off stays off, and a resting product is still on.

Paused logins don't count: if you paused a login yourself, it stays out of the judgement, as everywhere in ClaudeBar. A login with no data (not set up, or a fetch that failed) is never counted as empty either.

## Seeing it anyway

**Show anyway**, on the page or in the notification, or `open "claudebar://show-anyway?provider=claude"` ([URL schemes](../../app/url-schemes/README.md)), draws it as usual again. It won't rest again until it has had room and emptied again, and that survives a relaunch.

**Turning the setting off** forgets it all: the product is drawn as usual.

## Gotchas

- **The reset is observed, not predicted.** ClaudeBar doesn't guess from a reset time; it waits for a refresh that shows room. A failing API delays the return.
- **A relaunch doesn't forget.** Resting, and *Show anyway*, are saved.
- **Alerts still fire.** Resting changes the look, not the numbers: the status alert for the product running out still arrives, and the menu-bar icon's colour still counts it.
- Rest news is a notification on this Mac. Webhooks hear quota and status alerts, not this.

## See also

- [Multiple accounts](../../providers/multi-account/README.md), for pause and the product switch
- [Settings](../../../settings.md), where the key lives
- [Design](design.md), for contributors
