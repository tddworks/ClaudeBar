---
description: Contributor design for the run-out forecast — the quota line that says when a window will run out against when it refills, why it is a pure kernel read, and the laws it must keep.
---

# Forecast — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Monitoring: the
> words and laws belong to the model
> ([CANONICAL §1, §4, §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: `README.md` (written with the build).

## 1 · What a person asks, and what is true

Mia's question is not *how much is left* — the menu bar already answers that —
but **"will it last until it resets?"**. Today the app answers it obliquely.
`Pace` prints *On track · Running hot · Room to spare*, which judges the rate
against a steady spend but never names the moment. A person about to start a
40-minute run wants the moment, not the adjective.

What is true: a `Quota` has a `left` and, when the vendor set one, a `window`
that refills at `resetsAt`. Between the window's start and now the quota has
been spent at some average rate, and the `Usage` already carries everything
that rate needs — `percentUsed` and how much of the window has elapsed
(`percentTimeElapsed`). **A forecast is what those facts say together**: at the
rate this window has been spent so far, when does it reach zero, and is that
before or after it refills.

Two numbers, one sentence:

- `runsOutIn: Duration` — when it reaches zero at the average rate.
- `beforeReset: Duration?` — how long before the reset that is; `nil` when it
  outlasts the reset.

The arithmetic is one line. With a window of length `D`, `E` elapsed and `U`
percent used, the time to zero is `left% × E / U`. A window spent at nothing
(`U == 0`) never runs out, and reads *Lasts until it resets*.

## 2 · Where it lives: a pure kernel read, no new state

The tempting design is to measure the burn from samples the Monitor takes
across refreshes. It is also unnecessary: the quota's own window already spans
the cycle, and `percentUsed ÷ percentTimeElapsed` **is** the average rate over
exactly that cycle. A reset starts a new window, so the average is always over
the current one — nothing to cut, nothing to keep, nothing to lose on restart.

So the whole feature is a **derived read on the kernel value**:

```swift
quota.forecast            // Forecast? — nil without a window, or a balance with no ceiling
```

`Forecast` is a value in `Quotas`, beside `Pace`. It needs no capability (a
provider declares nothing about it), no Monitoring observation, and no second
meter — nothing is fetched. The view renders it; the alert (below) follows a
refresh like every other destination.

**Forecast is not Pace.** `Pace` compares used against *time elapsed* — a
judgement, inside a window, with no unit. `Forecast` projects used forward to
zero — a duration, about the future. They answer different questions, so they
are different values, and one never stands in for the other.

## 3 · The words the screens print

*Runs out in 38m* · *3h before it resets* · *Lasts until it resets* ·
*No forecast yet* · *at this pace*

The card line sits under *Resets in 1h 12m*:

```text
Session   ·  62% left
Resets in 1h 12m · Runs out in 38m — 34m before it resets
```

## 4 · What this adds to the canonical model

**Tree** (CANONICAL §1), under `Quota`:

```text
│       ├── window: Window?                 WHEN IT REFILLS — length + resetsAt. "Resets in 2h 5m".
│       │                                   A prepaid balance has none
│       ├── forecast: Forecast?  DERIVED    "Runs out in 38m — 34m before it resets": at the average
│       │                                   pace this window has been spent, when it reaches zero,
│       │                                   against when it refills. nil without a window, and nil
│       │                                   for a balance with no ceiling (no share to project)
│       ├── status                          DERIVED — Left × StatusPolicy (× Window, when pace-aware)
│       └── pace                            DERIVED — needs a Window; otherwise unknown
```

**Reads** (CANONICAL §4):

```text
quota.forecast                       → Forecast?   at the current window's average pace: when it
                                                   runs out, and whether that beats the reset
```

**Laws** (CANONICAL §5):

| Law | Owner |
|---|---|
| a forecast is a READ — never stored on `Usage`, never a second meter; it is derived from the quota's own window and the usage the vendor already gave | `Quota.forecast` |
| a forecast exists only inside a window: without a `Window`, or for a balance with no ceiling, it is `nil` — *No forecast yet* — never a number invented from nothing | `Forecast` |
| **a forecast is the average pace of the CURRENT window** — a reset starts a new window, so the average never spans two cycles and nothing needs cutting | `Quota.forecast` · `Window` |
| a quota that outlasts its reset reads *Lasts until it resets*, never a run-out: the forecast never contradicts the vendor's window | `Forecast` |
| a forecast says *at this pace*: it is the window's average, not a prediction of the next burst, and the words never claim more | `Forecast` |

## 5 · The pieces

| Piece | Module | One job | Changes when |
|---|---|---|---|
| `Forecast` (`runsOutIn`, `beforeReset`, `outlastsReset`) | `Quotas` | the answer — a duration and whether it beats the reset | the words or the shape change |
| `Quota.forecast` | `Quotas` | the rule: window + used% + elapsed% → `Forecast?` | the rate rule changes |
| the card line | `App` (`Views`) | render the sentence under *Resets in…* | the layout changes |
| `ForecastAlerts` (optional) | `Domain/Alerting/Forecast` | tell the person once per window when the forecast says it runs out first | the alert rule changes |

No port, no repository, no new setting: a read and a view. The alert, when
built, gets its own port beside `QuotaAlerts` (Alerting) and follows
`onRefreshed` — the Monitor is never edited for it.

## 6 · Flows

- **A refresh lands** → `Usage` is replaced → `quota.forecast` answers again →
  the card re-renders. Nothing is stored, so nothing has to be invalidated.
- **A window resets** → `percentTimeElapsed` drops, `percentUsed` drops with
  it, and the average restarts over the new cycle. The reset *is* the cut.
- **The alert** (when built) → `onRefreshed` → `ForecastAlerts.review(login)`
  → once per window, when `beforeReset != nil`, notify; never again until the
  window resets.

## 7 · Surfaces

| Surface | Shows |
|---|---|
| the popover's quota card | the line under *Resets in…* — the default |
| the **All** page | the same line, on the quota that leads the card |
| the menu bar | an optional readout mode (*Runs out in 38m*), later |
| the notch | the run-out beside the reset, later |
| a notification | *Claude · work runs out 34m before it resets* — its own port, off by default |

## 8 · What could go wrong

- **A window that did not start full.** A quota seen for the first time
  mid-cycle averages over a cycle it did not observe from the start. The
  forecast is still the honest average of what the window *reports*, and it
  says *at this pace*; the measured-rate refinement is in §11.
- **A bursty spender.** The average hides a spike. That is the point of
  *at this pace*: it is a rate, not a promise, and `Pace` already names the
  "running hot" case beside it.
- **Idle time.** A window that sat idle lowers the average, so the forecast
  reads *Lasts until it resets* — true at the moment, and the number moves as
  soon as work resumes. Weighting recent activity is §11.
- **A hidden quota or a paused login.** Out of every judgement (CANONICAL §5),
  so no forecast line and no alert.
- **A balance with no ceiling.** No share, no window → `nil`. A money quota
  *with* a ceiling has a share and forecasts; a prepaid balance does not.

## 9 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| the forecast on another surface (menu bar, Touch Bar, notch, status export) | the page reads `quota.forecast` — nothing else |
| a different rate rule (weighted, active-only, sampled) | `Quota.forecast` — one function |
| a warning before the reset | `ForecastAlerts` |
| a forecast for a Cost or a Budget | `Budget` already has a period; a second `Forecast` over money |

## 10 · Considered and rejected

- **On `Usage`.** The usage is what the vendor said as of a moment; a forecast
  is about time passing, and storing it would make two identical usages
  unequal and go stale between refreshes.
- **A capability in the definition.** Nothing about a forecast is the
  provider's; it would put a block in the shared format for a universal fact.
- **Samples kept by the Monitor.** More accurate, and a second source of
  truth to persist, invalidate and lose on restart — for a number the window
  already answers. Kept as the §11 refinement, not the first build.
- **From Usage History days.** Daily granularity, and only for providers that
  declare a `usageHistory`; a quota can run out inside one day.

## 11 · Open

- **Measured vs implied rate.** The implied rate is the window's average; a
  measured rate (samples across refreshes, weighted to recent activity) would
  react to a burst. Worth it only if the average proves misleading in practice.
- **A minimum elapsed span.** `U ÷ E` with `E` of a few seconds and `U` of one
  point is noise. The build should require a small floor (say one minute, or a
  used% above a point) and answer `nil` below it.
- **The alert's wording and place.** Does a run-out alert sit beside the
  20%/critical status alerts, or replace them for windows that forecast?