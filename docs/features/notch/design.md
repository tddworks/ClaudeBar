---
description: Contributor research behind the notch Live Activity. Covers why the notch, prior art (boring.notch, DynamicNotch), the no-private-API decision, the priority rules, click-through, and what was tried and dropped.
---

# Notch Live Activity: design

User guide: [README.md](README.md). Mockup: [notch-live-activity.html](../../mockups/notch-live-activity.html).

The notch is a **view**, not a new source of truth. `QuotaMonitor` and `SessionMonitor` stay authoritative, per the single-source-of-truth rule in [ARCHITECTURE.md](../../architecture/ARCHITECTURE.md).

## The problem

ClaudeBar already knows everything worth knowing about a running session. `SessionMonitor` consumes a live hook stream (`SessionStart`, `UserPromptSubmit`, `SubagentStart/Stop`, `TaskCompleted`, `Notification`, `Stop`, `SessionEnd`) and keeps a `ClaudeSession` with `phase`, `activeSubagentCount`, `completedTaskCount` and elapsed time. `QuotaMonitor` holds every provider's remaining quota and reset window.

Before the notch, all of it reached the user through surfaces that are wrong for ambient state:

| Surface | Failure mode |
|---|---|
| **16 px status item** | Fits one number. Sits in a menu bar that macOS 15 crowds and truncates. You have to already be looking at it. |
| **User notifications** | Transient by construction. Focus modes swallow them. |
| **Popover** | Needs a click on a target you have to aim for. |

The gap is specific and daily: **you start Claude in a repo, switch to a browser, and lose all signal about whether it's working, blocked or finished.** The most expensive case is *blocked*: Claude waiting on a permission prompt while you read Slack, wasting time on a session that needs one keystroke.

`Sources/App/LiveActivity/LiveActivityManager.swift` is still a no-op placeholder, because ActivityKit is unavailable on macOS, even in macOS 26. The notch is the surface that's available today. It's the only region of the screen that's always visible, never covered by a window, and already where the user looks.

## Rules

What the notch shows is decided in one pure function, `NotchActivityResolver.resolve(sessions:quotas:headlineQuota:now:)`, which touches no AppKit. It returns one `NotchActivity`, or nil to hide the notch. Activities rank by severity:

| Severity | Activity | From |
|---|---|---|
| 5 | `awaitingInput` | Session phase `.awaitingInput`, set by the `Notification` hook with the prompt text |
| 4 | `finished` | Phase `.stopped` / `.ended`, for 4 s after `finishedAt` |
| 3 | `quotaThreshold` | The most depleted quota whose `QuotaStatus.from(percentRemaining:)` is `.critical` or `.depleted` (under 20% left) |
| 2 | `agentsWorking` | Phase `.subagentsWorking` |
| 1 | `working` | Phase `.active` |
| 0 | `quotaGlance` | The headline quota: the selected provider's `lowestQuota` |

Rules that follow (the resolver's are pinned by `NotchActivityResolverTests`):

- **A blocked human beats anything a machine is doing.** `awaitingInput` outranks everything and never expires on its own. Snooze doesn't hide it either.
- **"Done" briefly interrupts ambient state without ever hiding a blocked session.** It ranks above a quota alert but below `awaitingInput`, and after 4 s it gives way to whatever is next.
- **Ties go to the session waiting longest** (earliest `startedAt`).
- **Only `.critical` and `.depleted` take over the notch.** `.warning` is real but not urgent, and a notch that lights up at half a tank stops meaning anything.
- **The resting state is the quota, not blank.** A notch that goes blank between sessions has no reason to be on screen at all. The session states still carry the headline quota as a small gauge on the right.

### Scoped to the selected provider

Since [10381ca](https://github.com/tddworks/ClaudeBar/commit/10381ca), the glance, the threshold check, the panel's quota cards and today's usage all come from `monitor.selectedProvider`. Before that, the notch reported the menu bar's chosen quota and the panel mixed the most depleted quotas of every provider, and switching provider in the popover changed nothing. The cost: a quota past its threshold on a provider that isn't selected no longer takes over the notch. The menu bar and notifications still cover that case. **Refresh quotas** refreshes the selected provider only, because refreshing all of them to update one reading was work nobody asked for, and the loader stopped while others were still fetching.

### Driver-level rules

These live in `NotchWindowDriver`, because they need a clock or user action:

- **Sessions older than 10 minutes drop out.** The panel lists the active session plus recent ones that finished less than 10 minutes ago, at most three. Left unfiltered, a morning session would sit in the panel all day.
- **Snooze is time-boxed to 30 minutes.** A dismissal that never comes back looks the same as a broken feature.
- **Wake timers.** Nothing observable changes when a "done" flash or a snooze ends, so the driver schedules its own re-resolve for that moment.

### One session, not many

`SessionMonitor` tracks a single `activeSession`. A new `SessionStart` ends the current one and moves it to `recentSessions`. The original design had a "multiple sessions keyed by `cwd`" state, with the worst session winning the pill. That isn't built, because it needs `SessionMonitor` to hold several live sessions first. The resolver already takes a list and picks by severity, so that change would stay inside `SessionMonitor`.

## Prior art

Two open-source implementations were read end to end before designing this.

### boring.notch ([TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch))

A full menu bar and HUD replacement: media controls, calendar, battery, file shelf, AirDrop, webcam.

**What it gets right**

*Notch geometry.* `getClosedNotchSize()` in `sizing/matters.swift` is the definitive measurement, and it isn't obvious. The width is `screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4`. It comes from the *auxiliary areas either side* of the notch, because there's no notch API. `safeAreaInsets.top > 0` is the canonical has-a-notch check. On a display without a notch, the height falls back to the menu bar height (`frame.maxY - visibleFrame.maxY`), which is what makes a virtual notch on an external display look right.

*Fixed window, animated content.* The window is a constant canvas at the top centre and is never resized. The notch shape is drawn and animated *inside* it, because resizing an `NSWindow` every frame is visibly janky.

*`NotchShape`.* A SwiftUI `Shape` with inverted top corners built from quad curves, whose `animatableData` covers both corner radii so the corners round out as the notch expands. It descends from MrKai77/DynamicNotchKit. ClaudeBar adopted it.

*`sharingType = .none`*, which hides the notch from screen recordings with one line of public API. ClaudeBar **hasn't adopted this yet**, so the notch shows up in recordings.

**What we don't copy: private API, used extensively.** `CGSSpace(level: Int32.max)` (through `@_silgen_name` into `CGSSpaceCreate`) puts the window in its own top-level Space so it floats above full-screen apps. `dlopen` of SkyLight lets it draw on the lock screen. Both are undocumented, both break across macOS releases, and both rule out a Mac App Store build.

### DynamicNotch ([jackson-storm/DynamicNotch](https://github.com/jackson-storm/DynamicNotch))

Newer and better factored, and the more useful reference for *architecture* rather than geometry.

**The content model is the takeaway.** Content sources don't come from one view switching on a mode enum. They're values that conform to a protocol and compete by priority (`id`, `stackID`, `priority`, `isExpandable`, sizes, corner radii, `makeView`/`makeExpandedView`). A `NotchState` distinguishes `showLiveActivity` from `showTemporaryNotification(duration:)`, and a registry lists descriptors with priorities (`nowPlaying`, `download.active`, `focus.on`…).

This maps directly onto ClaudeBar's problem. Session activity, quota alerts and permission prompts are independent sources competing for one strip of glass. The live-versus-temporary split is the "attention states persist, Done flashes for 4 s" rule. ClaudeBar kept the idea and simplified it: one `NotchActivity` enum with a severity, and one pure resolver instead of a registry.

*Panel setup* is clean, and both projects landed on the same settings: `NSPanel`, `[.borderless, .nonactivatingPanel]`, `level = .mainMenu + 3`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, transparent, no shadow, no animation behaviour. ClaudeBar uses exactly this.

**Where it differs, and why we side with boring.notch:** DynamicNotch's panel overrides `canBecomeKey`/`canBecomeMain` to `true`, so the notch takes keyboard focus. That in turn needs a global click monitor and a 151-line outside-click handler to dismiss it. boring.notch returns `false` and never steals focus. ClaudeBar's notch has no text entry, so `false` is right: **the notch must never pull focus from the terminal the user is working in.**

DynamicNotch also uses SkyLight and `CGShieldingWindowLevel()` for the lock screen. Same exclusion as above.

### Comparison

| | boring.notch | DynamicNotch | **ClaudeBar** |
|---|---|---|---|
| Window | `NSPanel` `.mainMenu + 3` | `NSPanel` `.mainMenu + 3` | same |
| Canvas | fixed 640 × 210 | fixed 1000 × 1000 | fixed 900 × 420 |
| Takes key focus | no | **yes** | **no** |
| Notch shape | custom `Shape`, animatable radii | custom, animatable radii | boring.notch's |
| Content model | mode enum on one view | **priority protocol + registry** | severity enum + pure resolver |
| Private API | `CGSSpace` + SkyLight + `dlopen` | SkyLight + `CGShieldingWindowLevel` | **none** |
| Above full screen | yes (private) | yes (private) | `.fullScreenAuxiliary` only |
| Lock screen | yes (private) | yes (private) | no |
| Hidden from recordings | yes | — | no |
| Scope | system HUD replacement | system HUD replacement | **one domain, existing state** |

### The private-API decision

Declining `CGSSpace` and SkyLight costs two capabilities: the notch won't float over a full-screen app in the way a max-level Space does, and it won't appear on the lock screen. That's the right trade here, for three reasons that don't apply to either reference project:

1. **`Sources/App/entitlements.mas.plist` exists.** ClaudeBar targets the Mac App Store, where `dlopen` into a private framework gets the app rejected in review.
2. **Sparkle auto-updates raise the cost of breakage.** A private-API change in a macOS point release becomes a support burden across every installed copy.
3. **The use case doesn't need it.** ClaudeBar's user is in a terminal and an editor, not a full-screen game. `.fullScreenAuxiliary` covers the current full-screen Space, which is the case that actually happens.

Both reference apps replace the HUD, and that only works if they're always on top of everything. ClaudeBar's notch is a second view onto a menu bar app's existing state. The premise is different, and so is how much risk it can afford. (The Touch Bar feature made the opposite choice, because no public API can keep a Touch Bar up for a background app. See [touch-bar/design.md](../touch-bar/design.md#why-private-api).)

## Architecture

- **Domain** (`Sources/Domain/Notch/`): `NotchActivity`, `NotchActivityResolver` and `NotchMetrics`, all pure and all unit-tested.
- **Infrastructure**: `NSScreen+NotchMetrics` feeds raw `NSScreen` values into `NotchMetrics.measure(...)` and picks `preferredNotchScreen`, the first screen with a physical notch, else `main`.
- **App** (`Sources/App/Notch/`): `NotchWindowDriver` watches `app.notchEnabled` and, while it's on, reads `QuotaMonitor` + `SessionMonitor` through `ObservationRenderSync` and pushes `NotchContent` to `NotchWindowController`, which owns the `NotchWindow` panel and a SwiftUI root view.

It's the same pattern as `StatusItemLabelDriver`: SwiftUI's `MenuBarExtra` hosting doesn't drive it, because that hosting has gone quiet after sleep before (#192).

### Geometry

`NotchMetrics.measure` implements boring.notch's rule with two guards. A measured width under 100 pt is treated as a transient screen configuration and replaced by the 185 pt default, which is close to a 14"/16" MacBook Pro notch. A menu bar height of 0, meaning an auto-hidden menu bar, falls back to 32 pt. About half of installs are on external displays or Macs without a notch, so the virtual notch is a main path, not a fallback. `didChangeScreenParametersNotification` re-measures and repositions.

### Click-through

The canvas is far larger than the drawn notch and sits over the menu bar. **`hitTest` returning nil isn't click-through**: the window still swallows the click. The only thing that lets a click reach the menu bar underneath is `ignoresMouseEvents`. So the window ignores the mouse by default. A global `.mouseMoved` monitor, which unlike a keyboard monitor needs no Accessibility permission, switches `ignoresMouseEvents` off only while the pointer is inside the notch's rect plus 6 pt of padding. The same check drives hover-to-expand. It returns early when nothing changed, because writing an `@Observable` property fires observers even when the value is the same, and doing that on every mouse move would redraw the notch continuously.

### Theming

Both reference apps force `darkAqua`. ClaudeBar's notch region is always black, because it copies physical glass and a light-themed notch makes no sense. Status colours come from `theme.statusColor(for:)`, so custom status colours and High Contrast apply.

## Dead ends and lessons

- **Starting inside `App.init()`** ([0c39f66](https://github.com/tddworks/ClaudeBar/commit/0c39f66)). Creating the panel's `NSWindow` before SwiftUI had built a scene left `MenuBarExtra`'s popover at about twice its content size (400 × 671 around 300 pt of cards) for the whole process, and turning the notch off afterwards didn't undo it. The driver now waits for `didFinishLaunchingNotification`.
- **GlowEffectKit for the refresh state** ([dc36ebe](https://github.com/tddworks/ClaudeBar/commit/dc36ebe)). Its sweep is driven by `TimelineView(.animation)`, which doesn't advance in a window that's never key in an app that's never frontmost. Both are deliberate here, so the glow rendered one frame and froze. The dot-matrix loader in place of the quota bar says "refreshing" without an animation that has to be coaxed into running. Watch for the same trap with any `TimelineView` or animation-driven effect in the notch.
- **Drop a folder on the notch to start a session there.** Both reference apps have a file shelf, so it's the obvious thing to copy. It was cut:
  - *Wrong category.* Every other state answers "what is Claude doing?", and this one answers "start Claude". A notch that sometimes means status and sometimes means drop zone is a notch you have to think about.
  - *Cost is out of proportion.* It needs a drag monitor on each screen and staggered re-registration to survive Space transitions.
  - *The payload is worse than the plumbing.* Launching a specific terminal with `cd … && claude` is terminal-specific AppleScript, and effectively impossible under the MAS sandbox.
  - *Users already have faster paths*: `cd` and `claude`, or dragging the folder onto a Terminal tab.

## Open questions

- **Multiple live sessions**: see [One session, not many](#one-session-not-many).
- **Hide from screen recordings** with `sharingType = .none`. It's one line; the open part is whether it should be the default or a setting.
- **Focusing a session's terminal** from the panel needs Accessibility permission, which a sandboxed MAS build can't have. Keep it an optional non-MAS extra, not something the feature depends on.
- **Menu bar auto-hide.** Whether the notch should stay when the menu bar hides. Proposal: yes while an activity is live, otherwise no.
