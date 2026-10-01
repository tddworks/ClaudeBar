---
description: Send quota to your iPhone through the Notify! app, as a Lock Screen Live Activity, a Lock Screen widget gauge and a Home Screen widget. Use when linking a device or when a surface doesn't appear.
---

# Notify!

ClaudeBar can put your quota on your iPhone through [Notify!](https://getnotifyapp.com), a third-party app that shows content other programs push to it. You don't need a ClaudeBar iPhone app. It's off by default.

There are three surfaces, and each can be switched off on its own:

| Surface | Shows | Updates |
|---|---|---|
| **Live Activity** (Lock Screen) | "ClaudeBar", a bar and reset countdown for the worst quota, and up to six quota windows below | Pushed, at most once a minute |
| **Lock Screen widget** | One quota as a gauge: a bar on the rectangular widget, a ring on the circular one | When iOS redraws widgets, about every 15 minutes |
| **Home Screen widget** | The same content as the Live Activity, but it stays where you put it | When iOS redraws widgets, about every 15 minutes |

Percentages are **remaining**, so a full ring means a full quota. The worst quota leads. Credit-based quotas show their balance instead of a percentage.

## Setup

Everything is in **Settings → Notify!**.

1. Install [Notify!](https://getnotifyapp.com) on your iPhone (it also runs on Mac and in a browser through web push).
2. **For the Live Activity, open Notify! once on the iPhone or iPad you're publishing to.** Until you do, the device has nothing that lets another program start a Live Activity. The widgets don't need this.
3. In Notify!, copy your **device ID** and **device token**.
4. Paste them into **Device ID** and **Token**, then press **Save Link**. You can also paste a whole Notify! notification URL into Device ID, and ClaudeBar splits it into ID and token.
5. Optional: **Verify Device** checks the pair with Notify! and shows the device's name. It runs only when you press it, because Notify! allows only a few checks a minute.
6. Turn on **Publish to Notify!**.

Then set up the surfaces:

- **Live Activity**, **Lock Screen widget** and **Home Screen widget** are on by default once publishing is on. Turn off any you don't want.
- **Gauge provider** / **Gauge quota** choose what the Lock Screen widget shows. **Automatic** shows whichever quota needs attention most.
- **Home Screen widget**: needs a recent Notify! version. In Notify!, turn it on under **Settings → Home Screen Widgets**. Creating it puts nothing on screen by itself. Add it from iOS's own widget picker, as you would any widget.
- Add the Lock Screen widget from iOS's Lock Screen editor.

**Send Now** (under **Send an Update Now**) publishes immediately, so you can check it arrives without waiting for the next refresh. Saving the link does the same.

## Which ID to use

Notify! issues IDs for several kinds of destination, and not all of them can show every surface:

| ID looks like | Is | Live Activity | Widgets |
|---|---|---|---|
| `IO…` (16 chars), or 8 characters | iPhone or iPad | yes | yes |
| `MC…` | Mac | no | yes |
| `WB…` | Browser | no | yes |
| `GRP…` | Group | no | no |

With a Mac or browser ID, ClaudeBar disables just the Live Activity switch and says why. A group only forwards notifications to its members and has no screen of its own, so use the ID and token of a single device instead.

## What leaves your Mac

Provider names, quota window labels, remaining percentages or credit balances, and reset countdowns go to `push.getnotifyapp.com` and on to your device. No prompts, repository names, file paths or session content are sent.

The device token is stored in the **Keychain**, never in `~/.claudebar/settings.json`, and is never logged.

## Gotchas

- **"This device cannot show a Live Activity yet"**: open the Notify! app once on the phone, then press **Send Now**.
- **Live Activity dismissed**: if you swipe it away, ClaudeBar starts a new one on the next update. If you delete a widget in Notify!, ClaudeBar creates a replacement.
- **"Notify! is waiting N minutes before another Live Activity"**: Notify! limits how often a Live Activity can be started. Wait it out. Opening the Notify! app on the phone may clear it sooner. The widgets keep updating meanwhile.
- **Home Screen widget paused**: if Notify! hasn't switched on Home Screen widgets for your account, ClaudeBar pauses only that surface for six hours and tries again. The other two keep going.
- **The Live Activity ends after two hours without updates**, and the Home Screen widget dims. ClaudeBar republishes at least every 90 minutes while it's running, so this only happens when the Mac is asleep or ClaudeBar is closed.
- **Widgets lag behind the Mac.** iOS decides when widgets redraw, roughly every 15 minutes, so ClaudeBar doesn't send widget updates more often than that.
- **"Stored in ClaudeBar's app credentials rather than the Keychain"** appears on builds you compile yourself. They're ad-hoc signed, so the Keychain refuses them. The token then goes to ClaudeBar's app credential store, still not `settings.json`. Release builds use the Keychain.
- **ClaudeBar never takes over a Live Activity or widget you created with another script.** It always creates its own and keeps updating those.

## See also

- [design.md](design.md): the gateway API, publish cadence, error recovery, and why ClaudeBar builds on Notify! instead of its own iPhone app
- [Notch](../notch/README.md): the same idea on the Mac
