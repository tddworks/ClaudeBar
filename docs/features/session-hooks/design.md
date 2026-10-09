---
description: Contributor design for the popover's Claude Code card. Covers the strip, which sessions get a row, Done sessions grouped by repo, the counts, the phase colours, and which type owns each rule.
---

# Claude Code card: design

User guide: [README.md](README.md). Mockup: [design-concept/sessions-card/index.html](../../../design-concept/sessions-card/index.html).

**Status:** BUILT on `feat/sessions-strip`. Before it, the card listed every session, Done ones included, up to five, then *+N more done*.

## The problem

Ana keeps several terminals open ([USER_JOURNEYS](../../architecture/USER_JOURNEYS.md) *Follow*). Most of her sessions sit at their prompt between turns, so they are **Done**. Today the card gives each of them a row: five rows of *Done* (three from the same repo) sit at the top of the popover on every tab and push the quotas down. Finished sessions need nothing from her; the one that *Needs you* is what she opened the popover for.

## What the card shows

```
 ■■□□□□□ Claude Code                                          ▾     ← the strip: always
 1 needs you · 2 working · 5 done
 ─────────────────────────────────────────────────────────────────
 ● tinyshop   [Needs you]                              1m 03s         ← a row per session in play,
 ● claudebar  [Agents working]           ✓ 3  👥 2     4m 12s           most pressing first
 5 done ›                                                             ← opens the Done group
 ── opened ──────────────────────────────────────────────────────
 DONE
 ● claudebar ×3                                        just now       ← Done sessions, one row per repo,
 ● Subtitled                                           21m ago          the latest finish first
 ● catalog                                             2h 32m ago
```

| State | The card |
|---|---|
| One session | Unchanged: `SessionIndicatorView` |
| Several, all Done | The strip alone: *7 done · finished 2m ago*; ▾ opens the Done group |
| Several, some in play | The strip, a row per session in play (at most five, then *+N more*), and *N done ›* |
| Opened | The Done group under the rows; ▴ or *N done ›* closes it |

- **The strip** has a square per session in its phase colour, in prominence order. Past twelve squares it stops and the count line carries the rest.
- **The count line** sits under the title and counts three kinds, most pressing first: *needs you · working · done*. *Working* counts Working and Agents working together (the rows tell them apart). A kind with none is left out.
- **A Done row's time** is how long ago it finished: the latest finish in its repo (`finishedAt`), or when it started for a session idle since it opened.
- **Open or closed** is kept while ClaudeBar runs, so closing and reopening the popover keeps it. Closed at launch; not a setting.
- **The card's outline** is the theme's, like every card beside it. The phase colours live in the squares, the count line and the badges, never the border.

## Phase colours

`ClaudeSession.Phase.color` serves the menu bar glyph and the notch. This change moves two of them:

| Phase | Label | Was | Now |
|---|---|---|---|
| `awaitingInput` | Needs you | yellow | **red**: the one that wants a keystroke, the loudest colour |
| `subagentsWorking` | Agents working | blue | blue |
| `active` | Working | green | green |
| `stopped` | Done | orange | **grey**: needs nothing, recedes |
| `ended` | Ended | grey | grey |

The card sits among the quota cards, so it draws phases in the theme's own palette (`AppThemeProvider.color(for:)`): Needs you in `statusCritical` (the colour of *LOW*), Working in `statusHealthy`, Agents working in `accentPrimary`, Done in `textTertiary`. The meaning is the same as above; only the shade is the theme's.

## Laws and owners

Views render and tell; they never count, filter or group sessions. Each rule has one owner:

| Law | Owner |
|---|---|
| Sessions in order of need: Needs you → Agents working → Working → Done, then the one heard from last | `SessionMonitor.sessionsByProminence` (exists) |
| A session **in play** is any running session that isn't Done; they keep the order of need | `SessionMonitor.sessionsInPlay` (new) |
| The count line's kinds: needs you · working (Working + Agents working) · done, most pressing first, a kind with none left out | `SessionMonitor.tally` (new) → `SessionTally`: `needsYou`, `working`, `done` |
| Done sessions grouped by repo, each group's latest finish, latest group first | `SessionMonitor.doneByRepo` (new) → `[DoneRepo]`: `repoName`, `count`, `lastFinishedAt` |
| When a session last finished, falling back to its start while idle since opening | `ClaudeSession.finishedAt` (exists); the fallback lives in `doneByRepo` |
| A phase's colour: in the menu bar and notch; in the card, in the theme's palette | `ClaudeSession.Phase.color` · `AppThemeProvider.color(for:)` (App) |
| Rows before *+N more* (5), squares before the strip stops (12), open or closed | `SessionsCardView`: presentation, not a rule |

`SessionTally` and `DoneRepo` are values in Activity beside `ClaudeSession`. Nothing new is stored: every query reads `sessions`, which stays the source of truth.

## Tests

`SessionMonitorTests`, Chicago school, one per law:

- should list only the sessions that aren't done, most pressing first
- should count sessions with agents as working
- should count each kind of session: needing you, working, done
- should fold done sessions in the same repo into one, with the latest finish
- should put the repo that finished last first
- should date a done session that never ran a turn from when it started
