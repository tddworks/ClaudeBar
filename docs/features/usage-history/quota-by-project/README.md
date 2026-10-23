---
description: Beside the model mix, the popover can split a login's year by the project it was spent in — which folders your tokens and cost went to, largest first. Use when the projects card is missing or a share looks off.
---

# Quota by project

Beside *Model mix — last year*, the popover can show **Projects — last year**: the same login's year split by the working directory each record was spent in, largest first — *marron 41%, api 33%, …*.

| Card | Shows |
|---|---|
| **Projects — last year** | One bar split by project and a row each, largest first, with the project's total and its share of the year. A project is the folder you ran the tool from, named by its last path component — *marron*, never `/Users/you/…/marron`. Shown only when the log records a directory. |

It reads the same days the heatmap and the model mix read — nothing new is fetched, and nothing is sent anywhere.

## Quick start

The card is **off by default**, like the other year sections. Turn it on in Settings → **General** → **Usage in the popover** → **Projects**.

It appears for logins whose tool records the working directory on the log lines ClaudeBar reads — **Claude Code** does, on every line. Other providers keep no directory on the records read today, so their logins show no projects card rather than a made-up split.

## How the numbers are worked out

- **A project is where you ran the tool.** Claude Code writes its working directory (`cwd`) on each log line; the folder's last path component is the project's name. Run from `~/code/marron`, the usage reads *marron*.
- **The parts add up.** The records a log writes without a directory form one unnamed part, shown last, so the card's shares always add up to 100%. A provider that records no directories at all shows no card at all.
- **The ledger keeps names, never paths.** Closed days are kept in `~/.claudebar/usage-history/` with the short project names — no absolute path with your username is ever stored or shown.
- **Two folders, one name.** Projects are named by their last folder component, so `~/code/marron` and `~/other/marron` read as one *marron* — the price of a name a person can read.
- **The unit follows the login**: dollars when the login's days hold a cost, tokens when none does — the same rule the model mix keeps.

## Gotchas

- **No projects card**: the section is off, or the provider's log writes no working directory (Codex, OpenCode, Mistral today).
- **The card's first appearance takes a moment**: turning on any year section reads a year of logs once; after that the closed days are kept and only today is re-read. Claude's kept days are summed again once, the first time after this change, so the split reaches the past.
- **A share looks smaller than expected**: that login's year includes records from before Claude Code wrote `cwd` on every line; they sit in the unnamed part.

## See also

[design.md](design.md) — the capture, the values and the laws · [usage insights](../insights/README.md) — the heatmap and the model mix the card sits beside · [daily usage](../daily-usage/README.md) — the days every one of them reads · [Claude](../../../providers/claude/README.md)
