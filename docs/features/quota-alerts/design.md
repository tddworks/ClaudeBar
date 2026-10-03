---
description: Contributor research behind below-threshold quota alerts. Covers the crossing evaluator and its hysteresis, where the state lives, persistence, and the designs that were rejected.
---

# Quota alerts: design

User guide: [README.md](README.md).

Issue #68 asks for notifications when usage falls below a user-defined threshold — ideally several. ClaudeBar already alerts on degradation into the fixed warning/critical/depleted states (50%/20%/0% in `QuotaStatus.from`), so the feature is a second, user-chosen set of boundaries layered on top of the existing alert path, not a replacement for it.

## The model

**`QuotaAlertThreshold`** (`Sources/Domain/Monitor/QuotaAlertThreshold.swift`) is the value type: a remaining percentage clamped to 0...100 at construction, `Codable`/`Comparable`/`Identifiable`, plus `displayLabel` ("35", not "35.0") for alert bodies and the settings list. Clamping in the initializer is the single normalization point — a stray hand-edited settings file can produce a threshold that never fires, never one that crashes.

**`QuotaThresholdAlertEvaluator`** owns the crossing semantics. It is a mutating struct, not a class or actor: its only caller is `QuotaMonitor`, which is `@MainActor`, so the state is owned value state with no synchronization story to tell. Per provider it keeps the set of thresholds currently "fired", and `crossings(providerId:percentRemaining:thresholds:)` returns exactly the thresholds newly crossed by this refresh:

| percent vs threshold | fired set | result |
|---|---|---|
| below, not yet fired | insert | fire |
| below, already fired | unchanged | silent |
| at or above threshold + margin | remove | re-armed |
| within margin above threshold | unchanged | stays fired |

The **recovery margin** (1 percentage point, constructor parameter) is the hysteresis that matters in practice. Without it, a quota oscillating 34.9/35.1 across refreshes fires on every dip; with it, a threshold must be cleared by a full point before it can fire again. Strictly below fires, at the threshold does not — "falls below" is read literally.

## Where the state lives

The evaluator instance is a property of `QuotaMonitor`, driven from `handleSnapshotUpdate` after the existing status-degradation alert. The alerter stays stateless: `QuotaAlerter` gained `alertThresholdCrossed(providerId:percentRemaining:threshold:)`, and `NotificationAlerter` only formats and sends (`QUOTA_THRESHOLD` category, body names the threshold and the current percentage). Splitting it this way keeps the fire-once-per-crossing rule in exactly one place — a second alerter implementation cannot re-spam.

Thresholds come from **`QuotaAlertSettingsRepository`**, a standalone Domain protocol beside `HookSettingsRepository` and `NotifySettingsRepository` — alerting is a destination, not a provider, so it never joins `ProviderSettingsRepository` (AGENTS.md; the Notify! design documents the same split). `QuotaMonitor` takes it as an optional init parameter; `nil` disables the feature entirely, which is what every existing call site and test gets by default.

## Persistence

`JSONSettingsRepository` conforms and stores plain `[Double]` under `alerts.thresholds`. Empty by default, so existing installs see no behavior change. Storing bare percentages (not encoded structs) keeps the file hand-editable and defers to the type's clamping on read.

## The settings UI

The editor lives in **Sync & Alerts**, the pane already named for alerts — not in General, and not in the Notify! pane. Add/remove goes through `AlertThresholdList.adding`, a pure function with the rules the view cannot get wrong: parse (`Double`, `%` and whitespace tolerated), clamp via `QuotaAlertThreshold`, reject duplicates, cap at eight. The count cap is arbitrary but bounded; an unbounded list would make the evaluator's per-refresh loop and the notification stream both user-hostage.

## Rejected designs

- **Per-provider thresholds.** The issue asks for user thresholds, full stop. A matrix multiplies the UI and the persistence for a need nobody stated; the crossing evaluator already handles any number of providers.
- **Putting threshold state in the alerter.** `NotificationAlerter` is swapped for mocks in tests and could be replaced wholesale; stateful alerters would each need their own dedup and would disagree after a swap.
- **Sending through Notify!.** Deliberately out of scope — Notify! is a display mirror with no threshold logic by design (see its design.md). Routing threshold alerts there is a plausible follow-up and touches none of this design's seams.
- **Scheduling or pace-aware thresholds.** The burn-rate machinery already covers "will run out too fast"; these thresholds are absolute levels.

## Testing

The evaluator and monitor wiring are covered by mock-free Swift Testing suites: `QuotaThresholdAlertEvaluatorTests` (crossing, refire, margin, per-provider isolation), `QuotaMonitorThresholdAlertTests` (recording alerter actor, threshold + fixed degradation alerts together, thresholds off), `JSONSettingsRepositoryAlertTests` (round-trip, reload, empty default), `NotificationAlerterThresholdTests` (recording sender, body names the threshold), and `AppSettingsAlertThresholdTests`/`AlertThresholdListTests` for the observable and the editor rules. The recording doubles are actors rather than Mockable mocks because the assertions are on resulting state anyway.
