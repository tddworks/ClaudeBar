---
description: Below the daily usage chart, the popover reads a login's last year — a heatmap of a cell a day, shaded by how full it was, and the model mix: which models you lean on, largest first. Use when the insights are missing or a number looks off.
---

# Usage insights

Below *Daily usage — last 30 days*, the popover reads the same login's **last year**, two ways:

| Card | Shows |
|---|---|
| **Usage — last year** | The year as a heatmap: a cell a day, shaded by how full it was against the busiest day. The year's total sits in the corner, and what prompt caching saved under it. |
| **Model Mix — last year** | One bar split by model and a row each, largest first, with the model's total and its share of the year. Shown only when the log names models. |

Both read the days the daily cards already read — nothing new is fetched, and nothing is sent anywhere.

## Quick start

The insights are **on by default** with the daily usage cards. Turn them off or on in Settings → **General** → **Daily Usage Cards**.

They appear for the same providers that keep local session logs (Claude Code, Mistral Vibe, Oh My Pi, OpenCode, and extensions). See [daily usage](../daily-usage/README.md) for the list.

## How the numbers are worked out

- **The year is read once.** The first time the insights appear, a year of the login's logs is read; after that the closed days are kept in `~/.claudebar/usage-history/` and only today's logs are read again. The chart's thirty days are the year's last thirty, not a second read.
- **A day is a cell, always.** Every date of the year gets one — a day with nothing used is an empty cell, never a gap. Its shade is how full it is against the busiest day in the year: darker is fuller.
- **The unit follows the login.** The insights open in dollars when a day of the login holds a cost, and in tokens when none does (a log that prices nothing, or writes $0 everywhere), never a made-up $0 — the same rule the daily chart keeps.
- **What caching saved** is the prompt-cache saving summed over the year, shown only when there is one.
- **The mix adds up.** A model's share is its part of the year's total. Records a log writes with no model form one unnamed line, shown in the mix too, so the parts always add up to the whole.

## Gotchas

- **The insights' first appearance takes a moment**: the first time, a year of logs is read; after that the closed days are kept and only today is read.
- **No insights at all**: the daily usage cards are off, or the provider keeps no local logs (Codex, Gemini, Copilot and the others).
- **A quiet day is not a gap**: weekends and days off show as empty cells in the heatmap; they never shorten the year.
- **The mix is missing**: the log doesn't name models, so there is nothing to split — the heatmap still shows.
- **The heatmap fits**: the year shares the popover's width at every text size and never scrolls. If a wider range is ever wanted, the window the page asks for is the knob — see [design.md](design.md).

## See also

[design.md](design.md) — the values the insights build from a range of days · [daily usage](../daily-usage/README.md) — the cards and the chart the insights sit under · [Claude](../../../providers/claude/README.md)