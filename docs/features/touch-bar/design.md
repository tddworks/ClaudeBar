---
description: How the Touch Bar feature works, for contributors. Covers the always-on bar through private system-modal API, the in-app bar, the status.json export, and why the animated mascot was removed.
---

# Touch Bar: design

User guide: [README.md](README.md).

The feature has three independent parts, all switched by `app.touchBarEnabled` (default `true`):

| Part | Where it shows | How |
|---|---|---|
| Always-on bar | Every app and full-screen Space | Private system-modal Touch Bar API |
| In-app bar | While ClaudeBar's popover or Settings window is key | Public `NSTouchBar`, set on the window and on `NSApp` |
| `status.json` export | Anything that reads `~/.claudebar/status.json` | File written on every distinct state |

All three read `QuotaMonitor` and `AppSettings` through `ObservationRenderSync`, the same way the status item and the notch do. Output is recomputed and pushed only when the observed state produces a different value, so an idle Mac does no Touch Bar work.

## Always-on bar

### Why private API

AppKit only lets the frontmost app own the Touch Bar. A menu bar app is almost never frontmost, so public API can only show quota while the popover is open, which defeats the purpose. The always-on bar uses the same system-modal path the Control Strip uses:

- `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]` with **`placement: 0`**, reached with `class_getClassMethod` and called through its IMP. Placement 0 is the modal function row that stays up across app switches.
- `+[NSTouchBar dismissSystemModalTouchBar:]` to take it down.
- `DFRSystemModalShowsCloseBoxWhenFrontMost(false)` from `/System/Library/PrivateFrameworks/DFRFoundation.framework`, loaded with `dlopen`, so the modal bar doesn't show a close box.
- After presenting, `+[NSFunctionRow _topLevelFunctionRowViews]` is walked and any button that looks like a close or dismiss control (title `x`/`esc`, image name containing `close`/`dismiss`, or action `dismiss:`) is hidden. The DFR call doesn't catch all of them.
- An empty, zero-width item replaces the Escape key (`escapeKeyReplacementItemIdentifier`), so the system Escape key and Control Strip keep working.

Each lookup is guarded, so a missing symbol means no bar rather than a crash. The notch made the opposite choice and uses no private API; its reasons are in [the notch design](../notch/design.md#the-private-api-decision).

### Staying up

macOS takes the modal bar away on some transitions, so the driver presents again, which is cheap and idempotent, on:

- `NSWorkspace.didActivateApplicationNotification` (any app switch)
- the distributed `com.apple.screenIsUnlocked` notification
- every render where the setting is on and there's at least one gauge

With no gauges, or with the setting off, it dismisses.

### What a gauge is

One gauge per quota, built from the Menu Bar configuration: for each of the up-to-three `menuBarProviderIds`, its primary quota (matched by key, falling back to the first quota), then its secondary quota when one is configured and differs. A provider with no snapshot still gets a placeholder gauge, so it shows `—` instead of disappearing.

- **Name:** the provider name, plus the quota's `menuBarTitle` / `compactTitle` / `shortLabel` when the provider contributes two gauges and the name doesn't already contain it. Antigravity uses the pool title alone, without the provider name.
- **Reset text:** `compactResetTime` first, then a countdown from `resetsAt` (`Nd`, `H:MM`, `Nm`), then `resetText` with the "Resets in" prefix removed.
- **Percent:** `displayPercent(mode: usageDisplayMode)`, clamped to 0 to 100.
- **Status:** computed with pace awareness when burn-rate warnings are on. `TouchBarProviderGauge.tone` maps it to the colour tier the view draws (`healthy` blue, `warning` amber, `alarm` red with `!` for critical and depleted, `none` dimmed with no bar). Before that, the view thresholded the displayed percentage instead (blue below 50, amber 50 to 89, red at 90 or more), which was right only in Used mode and inverted in Remaining and Pace: 93% remaining drew red and 18% remaining drew blue.

### Drawing

`TouchBarQuotaView` is one `NSView` on a fixed 600 × 30 pt canvas, drawn in `draw(_:)` with AppKit. Cells share the width evenly (at least 80 pt each), are centred, and drop the reset text below 120 pt and the name below 100 pt. Icons come from the asset catalog through `ProviderVisualIdentityLookup` and are cached whenever the gauge list changes. Providers without an asset (extensions included) fall back to their SF Symbol.

Tapping anywhere opens `claudebar://open`, which goes through the app's own URL handler.

`triggerRefreshPulse()` prefixes the percentages with 🔄 for 1.2 s. It's called from the in-app bar's Refresh button.

### Removed: the pixel mascot and global keyboard monitor

v0.4.90 put "Clawd" at the left of the bar: an animated 20 × 20 pixel mascot whose speed, eyes and colour reflected the heaviest quota. A `GlobalKeyboardMonitor` made it react to typing in any app. Both were removed in v0.4.92 ([a294da1](https://github.com/tddworks/ClaudeBar/commit/a294da1), [#292](https://github.com/tddworks/ClaudeBar/pull/292)) and replaced by the static `TouchBarQuotaView`:

- **The keyboard monitor needed Accessibility permission.** It was a listen-only `CGEventTap` that called `AXIsProcessTrusted()` and showed the system prompt when the Touch Bar driver started, which is at launch. Users saw an unexplained new permission request, and one reported the app no longer starting ([#290](https://github.com/tddworks/ClaudeBar/issues/290)).
- **The mascot redrew all the time.** A 30 fps `Timer` drove the animation even when nothing had changed. The replacement redraws only when the gauges change.

Don't bring back anything that needs Accessibility permission or a frame timer. The README promises neither.

## In-app bar

`NativeTouchBarDriver.makeTouchBar()` builds a bar with a provider badge, a scrolling provider picker, flexible space, Refresh and Settings. `TouchBarWindowAccessor`, a zero-size `NSViewRepresentable` in the background of `MenuContentView` and `SettingsWindowView`, installs it on its window and on `NSApp` once it's in a window, and clears both when the setting is off. Both views also attach the same content declaratively with `.touchBar { ClaudeBarNativeTouchBar }`. That copy's Refresh button doesn't trigger the 🔄 pulse.

## `status.json` export

`StatusExportDriver` writes `~/.claudebar/status.json` (pretty-printed, sorted keys). It writes to a temporary file in the same folder and swaps it in with `replaceItemAt`, so readers never see a partial file. `updatedAt` is set at write time and left out of equality, so a render that changes nothing doesn't rewrite the file just to move the timestamp.

- `menuBarText` and the top-level `status` come from `QuotaMonitor.menuBarLabel(...)` with the menu bar's own settings, so they match the status item. The status falls back to the selected provider's overall status, then to `unknown`.
- `providers[]` covers every enabled provider using `quotas.first ?? lowestQuota`, which isn't necessarily the quota the menu bar shows for it.
- The export is gated on `touchBarEnabled`, so turning the Touch Bar off also cuts off every other reader of the file. The README warns about this.

`scripts/touchbar_status.py` is the one consumer in the repo. It maps `status` to BTT colours and MTMR emoji, and looks for icons in `~/.claudebar/icons/` and `scripts/icons/`. Neither folder is created or filled by ClaudeBar.
