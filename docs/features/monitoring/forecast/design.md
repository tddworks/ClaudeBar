---
description: Contributor design for the run-out forecast — the quota line that says whether a window lasts until it refills, the one spend rate it shares with Pace, and the laws it must keep.
---

# Forecast — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Monitoring: the
> words and laws belong to the model
> ([CANONICAL §1, §4, §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md).

## 1 · What a person asks, and what is true

Mia's question is not *how much is left* — the menu bar already answers that —
but **"will it last until it resets?"**. `Pace` judges the speed (*On track ·
Running hot · Room to spare*) but never names the moment. A person about to
start a 40-minute run wants the moment.

What is true: a `Quota` has a `left` and, when the vendor states one, a
`window` with a length and a reset. Between the window's start and now the
quota has been spent at some average **rate** — the share used over the share
of the window gone. That one rate answers every question about speed:

- **Pace** — how fast, in words.
- **The pace tick** (`PaceLevel`) — how fast, in six grades.
- **The pace-aware status** — whether to warn.
- **The forecast** — whether it lasts until it resets, and when it runs out.

A forecast is the rate carried forward to zero:

- `rate ≤ 1` → **lasts until it resets**.
- `rate > 1` → **runs out** in `left × length ÷ (100 × rate)`, which is
  `length × (used − gone) ÷ used` before the reset.

## 2 · The one rate, and who reads it

```text
Window            length · resetsAt            elapsed(at:) · untilReset(at:)  — it knows its cycle
SpendRate         percentUsed ÷ percentTimeElapsed      the ONLY owner of how fast a quota is spent
  │                 one used share: from percentLeft (a capped money quota by its money)
  │                 one noise floor: 3% of the window gone; none once the window is over
  ├ UsageQuota.rate        → SpendRate?     nil without a window length + reset, for a balance
  │                                         with no ceiling, under the floor
  ├ UsagePace(rate:)       Running hot ⇔ rate > 1 · On track ≤ 5 points under · Room to spare
  ├ PaceLevel(rate:)       the tick's six grades
  ├ QuotaStatus.from(…)    projects from the rate once 15% of the window has gone
  └ Forecast(rate:window:at:)
                           nil once used up, or without a window length/reset
                           .lastsUntilReset ⇔ rate ≤ 1
                           .runsOut(in:, beforeReset:)
QuotaCardText.forecastLine(for:)   the words, and only the words
```

`Forecast` is a value in `Quotas`, beside `UsagePace`:

```swift
public enum Forecast {
    case lastsUntilReset
    case runsOut(in: Duration, beforeReset: Duration)
}
quota.forecast            // Forecast? — the quota's answer; nil means no line
```

It is a **read**: nothing is stored, nothing is fetched, no capability is
declared. A reset starts a new window, so the rate always spans exactly the
current cycle.

**Two floors, two laws.** The rate's noise floor (3%) says when a rate exists
at all: before it, Pace is `unknown`, the tick has no grade and there is no
forecast. The status's 15% is a different law — **when to warn**: a warning is
louder than a word, so the pace-aware status keeps its absolute thresholds until
15% of the window has gone. It reads the same rate once it projects.

## 3 · The edges

| The quota | Rate | Pace | Forecast |
|---|---|---|---|
| 52% used, 50% of the window gone | 1.04 | *Running hot* | *Runs out in 2h 18m — 11m before it resets* (5h window) |
| 50% used, 50% gone | 1 | *On track* | *Lasts until it resets* — it reaches zero as it refills |
| 48% used, 50% gone | 0.96 | *On track* | *Lasts until it resets* |
| nothing used | 0 | *Room to spare* | *Lasts until it resets* |
| 1% used a minute into a week | none (under 3%) | `unknown` | none |
| used up (0% or over) | — | *Running hot* | none — it has already run out |
| a reset but no window length | none | `unknown` | none |
| a balance with no ceiling | none | `unknown` | none — no share to project |
| a capped money quota | from its money share | from its money share | from its money share |

*On track* is the band that lasts: up to 5 points under the time gone. A quota
even a point ahead of the window runs out before the reset, so it reads
*Running hot* — the badge and the line never contradict each other.

## 4 · The words the card prints

The line is its own row, under the card's *Resets in…* row, with an hourglass,
muted. Its tooltip is *at this pace*. It is printed only when `quota.forecast`
is not `nil`; the card does not decide whether there is a forecast.

| `Forecast` | The line |
|---|---|
| `.runsOut(in: 38m, beforeReset: 34m)` | *Runs out in 38m — 34m before it resets* |
| `.lastsUntilReset` | *Lasts until it resets* |
| `nil` | no line |

Durations print as *42s*, *38m*, *3h*, *1h 12m*, *2d 5h*.

When a grid hoists one shared countdown above its cards, each card still prints
its own forecast line.

## 5 · What this adds to the canonical model

**Tree** (CANONICAL §1), under `Quota`:

```text
│       ├── window: Window?                 WHEN IT REFILLS — length + resetsAt
│       ├── rate: SpendRate?     DERIVED    how fast it is spent against its window
│       ├── forecast: Forecast?  DERIVED    lasts until it resets, or runs out N before it does
│       ├── status                          DERIVED — Left × StatusPolicy (× rate, when pace-aware)
│       └── pace                            DERIVED — reads the rate; otherwise unknown
```

**Reads** (CANONICAL §4):

```text
quota.rate                           → SpendRate?   used share ÷ window share gone
quota.forecast                       → Forecast?    lasts until it resets, or when it runs out
```

**Laws** (CANONICAL §5):

| Law | Owner |
|---|---|
| how fast a quota is spent against its window — one used share, one noise floor (3% of the window) — is ONE rate; pace, the tick, the pace-aware status and the forecast read it | `SpendRate` · `Quota.rate` |
| a forecast lasts until the reset ⇔ the rate is at most 1; otherwise it runs out in `left × length ÷ (100 × rate)` | `Forecast` |
| no forecast once the quota is used up, without a window length and reset, or without a rate | `Forecast` · `Quota.forecast` |
| *Running hot* ⇔ the forecast runs out before the reset | `UsagePace` |
| how a forecast is said on a card, and that it is said *at this pace* | `QuotaCardText` |

## 6 · The pieces

| Piece | Module | One job | Changes when |
|---|---|---|---|
| `Window.elapsed(at:)` · `untilReset(at:)` | `Quotas` | the cycle as of a moment | never, short of a new kind of window |
| `SpendRate` | `Quotas` | how fast, with the noise floor | the rate rule changes (weighted, measured) |
| `Forecast` | `Quotas` | the rate against the reset | the projection changes |
| `QuotaCardText.forecastLine(for:)` · `duration(_:)` · `forecastQualifier` | `App` | the words | the wording changes |
| `WrappedStatCard` | `App` | draw the line under the reset row | the layout changes |

No port, no repository, no setting.

## 7 · Flows

- **A refresh lands** → `Usage` is replaced → `quota.forecast` answers again →
  the card re-renders.
- **A window resets** → the share gone drops, the share used drops with it, and
  the rate restarts over the new cycle; under the floor there is no line until
  the rate exists.

## 8 · What could go wrong

- **A window first seen mid-cycle** averages over a cycle ClaudeBar did not
  watch from the start. It is still the honest average of what the window
  reports, and it says *at this pace*.
- **A bursty spender** hides a spike in the average; *Running hot* names it.
- **Idle time** lowers the average, so the line can read *Lasts until it
  resets*, true at that moment.
- **A hidden quota or a paused login** is out of every judgement, so no line.

## 9 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| the forecast on another surface (menu bar, notch, status export) | that page reads `quota.forecast` and words it |
| a different rate (weighted, measured from samples) | `SpendRate` — Pace and the forecast follow together |
| a warning before the run-out | a new alert beside `QuotaAlerts`, following `onRefreshed` |

## 10 · Considered and rejected

- **A rate of its own for the forecast.** A second "used" or a second floor
  lets the card print *On track* beside *Runs out before it resets*.
- **On `Usage`.** A forecast is about time passing; storing it would go stale
  between refreshes.
- **A capability in the definition.** Nothing about a forecast is the
  provider's.
- **Samples kept by the Monitor.** A second source of truth for a number the
  window already answers.

## 11 · Open

- **Measured vs implied rate.** A measured rate (samples across refreshes)
  would react to a burst; worth it only if the average proves misleading.
- **A run-out alert**, and whether it sits beside the status alerts.
