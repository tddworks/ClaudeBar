---
description: Contributor design for Refresh faster while a quota moves (#642) — AdaptiveCadence halves the background wait when a quota rose since the last tick and doubles it back to the chosen interval. Read before touching QuotaMonitor.startMonitoring's sleep, RefreshLoopKey or the Sync & Alerts pane.
---

# Refresh faster while a quota moves: design

User guide: [README.md](README.md). Issue: [#642](https://github.com/tddworks/ClaudeBar/issues/642).

**Status: BUILT.** `AdaptiveCadence` (Domain), the `adaptive` flag on `QuotaMonitor.startMonitoring`, `app.adaptiveRefreshEnabled`, and the switch in Settings → Sync & Alerts.

## The one sentence

**After each background tick, the next wait halves if a quota rose by a point since the previous tick, and doubles if none did, between one minute and the chosen interval.**

## Where it sits

```
 SyncAlertsPane switch ─▶ AppSettings.adaptiveRefreshEnabled ─▶ app.adaptiveRefreshEnabled
        │
 StatusItemLabelDriver.RefreshLoopKey(adaptive:) ── a change restarts the loop, as the interval does
        ▼
 QuotaMonitor.startMonitoring(interval:providerIds:adaptive:)
        │ each tick: refresh → readings(for:) → AdaptiveCadence.next(after:) = requested
        ▼
 effectiveInterval(requested:floors:) → × battery multiplier → clock.sleep
```

`AdaptiveCadence` only replaces the *requested* interval. Everything after it is unchanged: the 1-minute floor (#67), a provider's `backgroundRefreshFloor`, the battery multiplier and the display-sleep pause (#204). With the setting off the loop has no cadence and requests `interval` every tick, as before.

## Decisions

1. **The change since the last tick, not `PaceLevel`.** Pace projects `used / elapsed` over the whole window, so a 5-hour window quiet for four hours reads comfortable while the last twenty minutes burn fast.
2. **One point, one value for every window.** The reporter agreed on #642: both windows roll together, so a per-window threshold adds a setting without a case.
3. **Halve and double, not a jump.** One busy tick shortens the wait a little; a run that keeps going reaches a minute in four ticks. One quiet tick doesn't drop straight back.
4. **A reset is not movement.** A quota counts only when it was seen both times within the same window: both `resetsAt` absent, or within 15 minutes of each other. A reset read as "in 3h 20m" drifts by a minute each probe; a new window moves it by hours. A quota that appears or falls is not movement either.
5. **What this tick refreshed, as the person sees it.** Readings come from `usage(of:)` for the logins whose refresh succeeded this tick (`refreshAnswering` answers their ids), so a hidden quota (#140) doesn't count, as it sets no status. A login whose refresh failed or was paused is left out: it still holds its last snapshot, perhaps one an interactive refresh read between ticks, and a failure must not shorten the wait. It then has no reading to compare at the next tick, which counts as no movement.
6. **Off by default.** At worst it polls once a minute, and #204 chose a longer default for energy.

## Tests

| Test | Covers |
|---|---|
| `AdaptiveCadenceTests` | first tick waits the interval; halves to a minute; doubles to the interval; 0.5 point isn't movement; a new window isn't; a drifting reset time is the same window; any one quota counts; a new or falling quota doesn't |
| `QuotaMonitorTests` (#642) | a `TickingClock` run sleeping 10, 5, 2.5, 5, 10 minutes; a 15-minute provider floor stays 15 while moving; the setting off sleeps the interval every tick; a tick at 10%, an interactive refresh at 15%, then a failed tick keeps 10 minutes |
