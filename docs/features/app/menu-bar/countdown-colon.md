# Countdown Colon

The menu bar duration readout (`0h 98% · 4:40`) now advances on its own clock, and pulses the `:` separator to show that it is live.

---

## The problem

The countdown *value* was always correct when drawn. `MenuBarDurationDisplay.text` is a computed property, resolving through `UsageQuota.compactResetTime` → `resetsAt.timeIntervalSinceNow`, specifically so it reflects the current wall clock on every draw rather than freezing at construction time.

What was missing was anything to *cause* a draw on a time basis. `StatusItemLabelDriver` paints through `ObservationRenderSync`, which re-runs only when an `@Observable` property it read changes — and wall-clock time is not observable. So the label repainted only as a side effect of something else:

| Trigger | Source |
|---|---|
| Probe snapshot / settings / session-phase change | `currentLabelContent()` |
| Background refresh tick | `restartMonitoring`'s stream consumer |
| Claude Code hook event → `sessionMonitor.activeSession` mutation | `ClaudeBarApp.startHookServer` |
| System wake | `NSWorkspace.didWakeNotification` |
| Dropdown open/close | `reassertPresentation()` |

The hook path is why the countdown *looked* like it worked: while Claude Code is running, `PreToolUse`/`PostToolUse`/`Stop` events fire constantly, mutating `activeSession` and re-rendering the label many times a minute. Take that away — Claude Code idle or quit, and `app.backgroundSyncEnabled` defaulting to `false` — and the label could sit visibly stale until the user opened the dropdown.

A stale-but-plausible countdown is worse than an obviously missing one: nothing distinguishes a correct `4:40` from one frozen twenty minutes ago.

## Behavior

- A **1s tick** runs whenever a duration is shown (`menuBarDurationEnabled`). Every tick re-reads the label, so the countdown lands within about a second of the true minute boundary regardless of probe activity, hook traffic, or background-refresh setting.
- When the countdown is in **H:MM** range, the `:` fades to **25% alpha** on alternate seconds and back — a slow pulse that still reads as live.
- Actual status-item writes are coalesced to **at most one per second** (with a trailing flush), so the pulse beats at 1 Hz. The tick rate matches the write gate on purpose: a 0.5s tick under a 1s gate would replace the bright phase with the dim one inside every window, leaving the colon permanently dimmed. The gate exists because rapid renders must not stream straight into the system's status-item service — on macOS 26 that service aborts under the load and the item disappears ([#281](https://github.com/tddworks/ClaudeBar/issues/281)).
- Both menu bar layouts pulse: the single-line label and each line of the stacked dual-window label (both share one phase, so the two colons pulse together rather than drifting).
- No new setting. The pulse rides on the existing "Show duration" toggle.

```
0.0s   0h 98% · 4:40 | Fable 22% · 2d     ← written (colon full alpha)
1.0s   0h 98% · 4 40 | Fable 22% · 2d     ← written, colon at 25% alpha (still drawn)
2.0s   0h 98% · 4:40 | Fable 22% · 2d     ← written, colon back to full
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      Domain (tested)                                      │
│                                                                           │
│   UsageQuota.compactResetTime ──▶ "4:40"        (unchanged)               │
│                                                                           │
│   CountdownColon.ranges(in:) ──▶ [Range<String.Index>]                    │
│     matches \d(:)\d\d only — a probe's menuBarTitle colon never pulses    │
│                                                                           │
│   ObservationRenderSync.refreshNow()  ★ new entry point                   │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
┌──────────────────────────────────────────────────────────────────────────┐
│                      App — StatusItemLabelDriver                          │
│                                                                           │
│   blinkSync : ObservationRenderSync<Bool>                                 │
│     watches menuBarDurationEnabled ──▶ start/stop blinkTimer              │
│                       │                                                   │
│                       ▼                                                   │
│   blinkTimer (1s, RunLoop .common mode)                                   │
│     every tick: blinkPhase.toggle() ──▶ labelSync.refreshNow()            │
│                       │                                                   │
│                       ▼                                                   │
│   LabelContent { …, colonVisible: Bool }                                  │
│     colonVisible alternates ONLY when the label holds a countdown colon   │
│                       │                                                   │
│         ┌─────────────┴──────────────┐                                    │
│         ▼                            ▼                                    │
│   StatusBarPercentage-        StatusBarStacked-                           │
│   ImageRenderer               ImageRenderer                               │
│         └─────────────┬──────────────┘                                    │
│                       ▼                                                   │
│   CountdownColonStyle.apply(colonVisible:to:baseColor:)                   │
│     dims the colon ranges inside the NSAttributedString                   │
│                       ▼                                                   │
│   StatusItemWriteGate  (issue #281)                                       │
│     coalesces renders: ≤1 button write/second + trailing flush            │
│                       ▼                                                   │
│              statusItem.button.image                                      │
└──────────────────────────────────────────────────────────────────────────┘
```

## Design decisions

### Fade the colon, never hide it

The label draws in `monospacedDigitSystemFont`, where only the **digits** are fixed-width — punctuation stays proportional. Substituting a space for the colon would change the label's width twice a second and shove every menu bar item to its left. So the glyph always draws at full size and only its alpha changes: identical metrics in both phases, one attributed-string draw, no layout jitter.

25% rather than 0% also keeps the time reading as a complete value; a fully vanishing colon reads as a dropped character.

### `refreshNow()`, not `renderNow()`

Each `ObservationRenderSync.sync()` arms a **new** `withObservationTracking` registration, and a registration is only torn down when it fires. A caller ticking at 2 Hz through `renderNow()` would accumulate one armed registration per tick — roughly 1,200 over ten idle minutes — all watching the same properties, then fire the entire backlog in a single burst on the next probe result, each spawning a Task that re-arms.

`refreshNow()` re-reads and renders **without** arming a new registration. This is safe because the registration from the last real `sync()` is still armed and still catches genuine state changes; reading the values untracked does not consume it. It also keeps the equality check that `renderNow()` deliberately bypasses.

### `colonVisible` only alternates when there is a colon

For a `2d` or `45m` label the flag stays constant, so `LabelContent` compares equal across ticks and `render()` early-outs before touching the image. Those labels get the freshness fix (they still recompute, so `45m` → `44m` lands on time) at the cost of one struct comparison per tick, with no repaint until the text genuinely changes.

### Writes coalesce to at most one per second

The blink originally painted straight through: every changed `LabelContent` composed an image and re-set the button's tooltip and accessibility label, twice a second for an H:MM countdown. That is a stream of updates into the Control Center status-items XPC service, and on macOS 26.6 that service can abort inside its own serializer under exactly such a stream — the app dies four times a day and the menu bar item vanishes ([#281](https://github.com/tddworks/ClaudeBar/issues/281)).

`StatusItemWriteGate` sits between `render()` and the button: the first write goes out immediately, renders landing inside the one-second window only replace the pending content, and a single trailing flush publishes the latest content when the window closes. The tick rate matches the gate (1s), so each blink phase lands on a window boundary and the phases keep alternating; a 0.5s tick under this gate would replace the bright phase with the dim one inside every window and leave the colon permanently dimmed. Tooltip and accessibility text are skipped entirely when unchanged, which removes the remaining per-tick string writes. The Apple-side abort itself cannot be reproduced in a unit test; the tests pin the update-rate reduction.

## Scope

The colon only exists in the **1h–24h** range — that is the shape `compactResetTime` emits. Below an hour (`45m`), above a day (`2d`), and the sub-minute `soon` have no separator to pulse. Those labels get the self-driven tick but no animation. Widening the animation would mean changing the compact time format itself, which is a separate decision.

## Files

| File | Change |
|---|---|
| `Sources/Domain/App/CountdownColon.swift` | New — locates countdown colons |
| `Sources/Domain/Monitoring/ObservationRenderSync.swift` | New `refreshNow()` |
| `Sources/App/StatusItemLabelDriver.swift` | Blink timer + lifecycle, `LabelContent.colonVisible`, `CountdownColonStyle`, both renderers |
| `Sources/App/StatusItemWriteGate.swift` | Coalescer gating all status-item writes (#281) |

## Tests

Logic lives in Domain where it can; the write gate is an App-layer concern (it schedules a main-runloop timer and drives `NSStatusItem`'s button), so it is tested in the App target.

- `Tests/DomainTests/App/CountdownColonTests.swift` — 12 tests: H:MM detection, dual-window labels, `45m`/`2d`/empty labels, colons that are not countdowns (`acct:main`, `4:4m`, `4: 40`), single-character ranges, and `NSRange` conversion against multi-byte text (`·`).
- `Tests/DomainTests/Monitoring/ObservationRenderSyncTests.swift` — 5 added tests for `refreshNow()`, including that it leaves observation armed so later state changes still render.
- `Tests/AppTests/StatusItem/StatusItemWriteGateTests.swift` — 8 tests for the gate: first write immediate, deferral inside the window, latest-content trailing flush, one write per second under a 0.5s render cadence, alternation surviving a tick that lands just inside the window, and no-op flushes.
