---
description: Contributor design for the popover's Claude Code card. Covers the strip, which sessions get a row, Done sessions grouped by repo, the counts, the phase colours, and which type owns each rule.
---

# Claude Code card: design

User guide: [README.md](README.md). Mockups: [design-concept/sessions-card/index.html](../../../design-concept/sessions-card/index.html), [design-concept/session-titles/index.html](../../../design-concept/session-titles/index.html) (titles).

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

## Session titles

**Status:** BUILT on `feat/session-names`.

Two terminals in one repo give two rows that read *claudebar*. Each session's title tells them apart, on a second line under the repo, in `textTertiary`, one line, truncated at the tail:

```
 ● claudebar  [Agents working]           ✓ 3  👥 2     4m 12s
   Show session names in the card                                      ← its title
 ● claudebar  [Working]                                   40s          ← no title yet: one line
```

- **The title** is the name the person gave the session (`/rename`), else the title Claude Code wrote for it. A session with neither, one that hasn't had a prompt yet, keeps its single line.
- **Where it comes from**: every hook event carries `transcript_path`, the session's JSONL transcript. Claude Code appends `{"type":"custom-title","customTitle":…}` when the session is renamed and `{"type":"ai-title","aiTitle":…}` for its own title, and re-appends both as the session goes on. The latest of each kind counts.
- **When it changes**: `/rename` fires no hook, so a new name shows at the session's next event (the next prompt, or the end of the turn).
- **Cost**: the reader keeps where it stopped in each transcript and reads only the bytes appended since, so a long session's transcript is read once, then in small steps.
- **Rows**: every row for one session shows its title, in play or Done. A folded Done row (*claudebar ×3*) stands for several sessions and shows none. The single-session card puts it on its own line under *Claude Code*.
- **Notifications** name the session by its repo, then its title: *claudebar · Show session names*, then the summary as before. A new session has no title yet; one resumed with `claude --resume` already has one.
- **The notch**: its open panel's session list puts the title under the repo, like the card. The closed bar beside the cutout keeps the repo alone: a title doesn't fit there.
- **Not here**: the menu bar.

| Law | Owner |
|---|---|
| A session's title: its name if it was given one, else Claude Code's, else none | `ClaudeSession.title` (new), from `named` and `generated` |
| The latest name and the latest Claude Code title in a transcript, reading only what was appended since the last read | `TranscriptTitleReader` (Infrastructure, new) behind the `SessionTitles` port (Domain, new, `@Mockable`) |
| The transcript a session writes to | `SessionEvent.transcriptPath` (new), parsed from `transcript_path` by `SessionEventParser` |
| The titles found in the transcript when the event arrived, when it names one | `SessionEvent.titles` (new): `TranscriptTitles` (`named`, `generated`) |
| A session takes the titles its events carry; an event that found none leaves them as they were | `SessionMonitor.processEvent` |
| A session's name in a notification: its repo, then its title when it has one | `ClaudeSession.repoAndTitle` (new) |
| A Done row's title: the session's, when the row stands for one session | `DoneRepo.title` (new), set by `SessionMonitor.doneByRepo` |
| Reading the titles for each event before the monitor sees it, off the main actor | `ClaudeBarApp`'s hook loop (the composition root) |

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
- should show a done session's title when it is alone in its repo
- should show no title for a repo's folded done sessions

`ClaudeSessionTests`: should title a session by its name over Claude Code's · should title a session by Claude Code's when it has no name · should have no title before either is known · should name a session by its repo and title.

`SessionMonitorTests` also: should title a session from its event · should keep a session's title when an event found none · should title an ended session from its last event.

`TranscriptTitleReaderTests`: should find the latest name and Claude Code title · should find a title appended after the last read · should keep the titles when nothing was appended · should find a title whose line was still being written at the last read · should read a transcript again from the start once it was rewritten shorter · should keep a name when a later one is blank · should have no titles for a transcript that doesn't exist.

`SessionEventParserTests`: should read the transcript a session writes to.
