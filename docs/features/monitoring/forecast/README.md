---
description: The line on a quota card that says whether the window lasts until it resets at the pace it has been spent, and when it runs out if not. Use when reading a quota card's hourglass line, or when a card shows none.
---

# Forecast

A quota card already says how much is left and when it resets. The **forecast** answers the question between them: **will it last until it resets?** It is its own muted line, with an hourglass, under the card's *Resets in…* row.

```text
Session                     62% left
(clock)     Resets in 1h 12m   Room to spare
(hourglass) Lasts until it resets
```

## The words

| The line reads | It means |
|---|---|
| **Runs out in 38m — 34m before it resets** | At the pace this window has been spent, it reaches zero 34 minutes before it refills |
| **Lasts until it resets** | At this pace (or with nothing spent) it is still there when the window refills |
| *(no line)* | Nothing to forecast: see below |

Hover the line for *at this pace*: the forecast is the **average** of the current window so far, not a promise about the next burst. A window resets to a fresh average, so the line moves with your work.

## It agrees with Pace

The forecast and the Pace badge read one rate: how fast the quota is spent against how fast its window passes. So they never contradict each other:

| Pace badge | Forecast |
|---|---|
| **Running hot** — more than 5 points ahead of the time gone | **Runs out in … before it resets** |
| **On track** — within 5 points of the time gone, either side | **Lasts until it resets** |
| **Room to spare** | **Lasts until it resets** |

52% used half way through a 5-hour window reads *On track* and *Lasts until it resets*; 60% reads *Running hot* and *Runs out in 1h 40m — 50m before it resets*.

## When a card shows no forecast line

- **The window's start is too recent.** Under 3% of the window gone (nine minutes of a 5-hour window, about five hours of a week) is noise, not a rate. Pace reads nothing then, either.
- **It is used up.** A quota at 0% (or over) has already run out.
- **The provider gives no window length**, only a reset time: there is no rate to measure.
- **A balance with no ceiling** (prepaid credits) has no share to project.
- A **hidden quota** and a **paused login** are out of every judgement.

## Good to know

- **A window first seen mid-cycle** averages over a cycle ClaudeBar did not watch from the start. The line is still the honest average of what the window reports.
- **A bursty spender** hides a spike inside the average; the *Running hot* badge beside it names that case.
- **An idle window** lowers the average, so the line can read *Lasts until it resets* — true at that moment, and it moves as soon as work resumes.

## See also

- [Forecast — design](design.md): the one rate it reads, and the laws it keeps
- [Status colors](../../quota/status-colors/README.md): the pace-aware warning beside it
- [Quota alerts](../../alerting/quota-alerts/README.md): a notification below a percentage
