---
description: The line under a quota's reset countdown that says when that window will run out at the pace it has been spent so far, and whether that beats the reset. Use when reading a quota card or when it says "No forecast yet".
---

# Forecast

A quota card already says how much is left and when it resets. The **forecast** answers the question between them: **will it last until it resets?** It sits under the *Resets in…* line and names the moment.

```text
Session   ·  62% left
Resets in 1h 12m · Runs out in 38m — 34m before it resets
```

## The words

| The line reads | It means |
|---|---|
| **Runs out in 38m — 34m before it resets** | At the pace this window has been spent, it reaches zero 34 minutes before it refills |
| **Runs out in 3h** | It reaches zero in 3 hours; the reset is further away |
| **Lasts until it resets** | Nothing has been spent yet, or the pace is slow enough that it will still be there when the window refills |
| **No forecast yet** | There is not enough to go on — no window length, or the window has only just begun |

The forecast is always *at this pace*: the **average** of the current window so far, not a promise about what happens next. A window resets to a fresh average, so the number moves with your work.

## How it is worked out

The quota's own window already holds everything the rate needs: how much of it has been spent (`used`) and how much of it has elapsed. The time to zero is simply

```text
left% × elapsed ÷ used%
```

Nothing is stored and nothing extra is fetched — the line is derived from the usage the provider already reported. It is deliberately not the same as **Pace** (*On track · Running hot · Room to spare*), which compares what is used against how much of the window has passed. Pace judges the rate; the forecast names the moment.

## Good to know

- **A window first seen mid-cycle** averages over a cycle ClaudeBar did not watch from the start. The line is still the honest average of what the window reports, and it says *at this pace*.
- **A bursty spender** hides a spike inside the average. That is the point of *at this pace* — and Pace already names the *Running hot* case beside it.
- **An idle window** lowers the average, so the line reads *Lasts until it resets* — true at that moment, and it moves as soon as work resumes.
- **A balance with no ceiling** (a prepaid credit balance) has no share to project, so it shows no forecast line.
- **A window spent at nothing**, or one less than a minute old, is noise rather than a rate: the line reads *No forecast yet* instead of inventing a number.
- A **hidden quota** and a **paused login** are out of every judgement, so they show no forecast line.

## See also

- [Forecast — design](design.md): why it is a pure kernel read, and the laws it keeps
- [Status colors](../../quota/status-colors/README.md): the pace-aware warning beside it
- [Quota alerts](../../alerting/quota-alerts/README.md): a notification below a percentage