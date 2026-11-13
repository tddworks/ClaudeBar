---
description: Contributor design for the popover's Claude Code card. Covers the strip, which sessions get a row, Done sessions grouped by repo, the counts, the phase colours, and which type owns each rule.
---

# Claude Code card: design

User guide: [README.md](README.md). Mockups: [design-concept/sessions-card/index.html](../../../../design-concept/sessions-card/index.html), [design-concept/session-titles/index.html](../../../../design-concept/session-titles/index.html) (titles).

**Status:** BUILT on `feat/sessions-strip`. Before it, the card listed every session, Done ones included, up to five, then *+N more done*.

## The problem

Ana keeps several terminals open ([USER_JOURNEYS](../../../architecture/USER_JOURNEYS.md) *Follow*). Most of her sessions sit at their prompt between turns, so they are **Done**. Today the card gives each of them a row: five rows of *Done* (three from the same repo) sit at the top of the popover on every tab and push the quotas down. Finished sessions need nothing from her; the one that *Needs you* is what she opened the popover for.

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

## Bring a session forward

**Status:** BUILT. Tried by hand in iTerm2; tmux, Ghostty (its AppleScript reads `working directory`, so two terminals in one folder go to the first) and the notch click are best-effort until tried. Mockup: [design-concept/session-focus/index.html](../../../../design-concept/session-focus/index.html).

Ana sees *tinyshop · Needs you* in the card. Today she then hunts through iTerm2's windows and tabs for it. Instead, clicking the row (or pressing its number) brings that terminal to the front, on the tab that runs the session.

```
 ■■■□□ Claude Code                                            ▾
 1 needs you · 2 working · 5 done
 ─────────────────────────────────────────────────────────────────
 1 ● tinyshop   [Needs you]                              1m 03s     ← click, or press 1: iTerm2 shows this tab
 2 ● claudebar  [Agents working]           ✓ 3  👥 2     4m 12s
     Show session names in the card
 3 ● claudebar  [Working]                                   40s
 5 done ›
 ── opened ──────────────────────────────────────────────────────
 DONE
 4 ● claudebar ×3                                      just now     ← the one that finished last
 5 ● Subtitled                                         21m ago
```

### Where it goes

| The session runs in | Clicking it |
|---|---|
| iTerm2 | Selects the tab and window that hold the session, then brings iTerm2 to the front |
| tmux, inside iTerm2 | Selects the pane and its window in tmux (zoomed out first if another pane is zoomed), then does the same as iTerm2's own row |
| tmux, inside another terminal | Nothing: the row is not clickable and has no number. tmux sets `TERM_PROGRAM` to `tmux`, so the terminal around it is unknown, and selecting the pane alone would leave that terminal where it is. Only iTerm2 says itself through tmux, in `LC_TERMINAL` |
| Ghostty | Focuses the Ghostty terminal whose folder is the session's, then brings Ghostty to the front |
| Terminal, Warp, WezTerm | Brings that app to the front; none has a way to name a tab from outside |
| Any other (an IDE's terminal: VS Code and Cursor say `vscode`, Zed `zed`; Hyper; kitty and Alacritty, which set no `TERM_PROGRAM`), hooks from before this change, nothing said | Nothing: the row is not clickable and has no number. A row is a button only when ClaudeBar knows the app by its bundle ID, so a click never does nothing |

- **What tells ClaudeBar where it runs**: the hook runs inside Claude Code's environment, so it sends what the terminal set there, in headers beside the process ID it sends today: `TERM_PROGRAM`, `LC_TERMINAL` (iTerm2 sets it, and it survives tmux), `ITERM_SESSION_ID`, `TMUX` and `TMUX_PANE`. A session takes the place it runs from its latest event that said one. Existing installs get the new hook at the next launch: ClaudeBar reinstalls its hooks when they are already on.
- **Sessions already running** say nothing until their next event (the next prompt or the end of a turn). Until then their row is not clickable.
- **A tab that has gone** (closed since): iTerm2 is brought to the front on whatever tab it shows, rather than nothing happening.
- **A folded Done row** (*claudebar ×3*) brings forward the session in that repo that finished last.
- **The popover closes** once a row is clicked or its number pressed: the person is on their way to the terminal.
- **The number keys**: plain **1**–**9** pick the card's rows top to bottom as drawn: rows in play, then the Done rows when the group is open. **0** is the tenth. A row hidden behind *+N more* has no number. **⌘0**–**⌘9** stay the provider pills. The one-session card answers **1**. A number shows beside each clickable row in `textTertiary`.
- **The notch**: clicking a session in its open panel does the same. No number keys there: it never takes the keyboard.
- **The first time**, macOS asks whether ClaudeBar may control iTerm2 (or Ghostty). Declined, the row still brings the app to the front.
- **The App Store build** is sandboxed: it can neither run `tmux` nor script iTerm2 or Ghostty without entitlements App Review questions. There a click brings the terminal app to the front, nothing more.
- **Not here**: opening a new tab for a session whose tab is gone; IDE sessions (VS Code, Zed, JetBrains); a global hotkey.

### Laws and owners

| Law | Owner |
|---|---|
| Where a session runs: which terminal, its iTerm2 session, its tmux pane and server, from what the terminal set in Claude Code's environment; nothing when it said nothing | `SessionTerminal` (Activity, new): built from the raw values by `SessionTerminal(environment:)`. iTerm2 when `LC_TERMINAL` is `iTerm2` or `TERM_PROGRAM` is `iTerm.app`; the iTerm2 ID is the UUID after `:` and only `[A-Za-z0-9-]`, else none |
| Where an event says its session runs | `SessionEvent.terminal` (new): the hook's `X-ClaudeBar-Env-<VARIABLE>` headers (`HookConstants.environmentHeader`), read by `HookHTTPServer`, turned into a `SessionTerminal` by `SessionEventParser` |
| A session takes the place its latest event names; an event that names none leaves it as it was | `ClaudeSession.terminal` (new), set in `SessionMonitor.processEvent` |
| Where a click brings a session: its terminal, when that names an app ClaudeBar brings forward, and its folder; nil otherwise, and then the row is no button | `ClaudeSession.place` (new) · `canBringForward` (`place != nil`) |
| Where a folded Done row goes: the place of its session that finished last | `DoneRepo.place` (new) · `canBringForward`, set by `SessionMonitor.doneByRepo` |
| Bringing a session forward | `SessionFocus` (Activity, new): `bringForward(_ session:)`, `bringForward(_ repo:)` hand the row's own `place` to the `TerminalFocus` port; it decides nothing itself |
| Telling the OS: tmux, then the terminal's tab or terminal, then the app; or the app alone when sandboxed | `TerminalFocus` port (Domain, `@Mockable`), `ScriptedTerminalFocus` (Infrastructure, new): AppleScript for iTerm2 and Ghostty, `tmux` by `Process`, `NSRunningApplication.activate()` |
| A row's number: its place among the card's drawn, clickable rows | `SessionsCardView`: presentation |

`SessionTerminal` is a fact about where a process runs; the bundle IDs, the scripts and `tmux`'s path are the adapter's, never the domain's. `TerminalFocus` takes a `SessionTerminal` and the session's folder (for Ghostty) and returns nothing: a terminal that can't be found is not an error the person can act on, and the adapter logs it under `AppLog.ui`.

### Tests

`SessionTerminalTests`: should run in iTerm2 when iTerm2 says so · should run in iTerm2 inside tmux · should keep only the iTerm2 session's own ID · should have no iTerm2 session when its ID isn't one · should run in tmux with its pane and server · should run in Ghostty · should name no app for a terminal it can't bring forward · should run nowhere known when nothing was said.

`SessionEventParserTests`: should read where a session runs from the hook.

`SessionMonitorTests`: should know where a session runs from its event · should keep where a session runs when an event doesn't say · should bring forward a repo's done session that finished last · should not bring forward a done repo whose latest session never said where it runs.

`ClaudeSessionTests`: should be brought forward only once it is known where it runs · should not be brought forward when only its tmux pane is known · should be brought forward in tmux when the terminal around it is known.

`SessionFocusTests`, on where a fake terminal ended up: should bring the clicked session's terminal to the front · should bring the latest session of a clicked folded repo to the front · should bring nothing forward when the session never said where it runs.

`HookInstallerTests`: should send where a session runs with each event.

## Work left running in the background

**Status:** BUILT on `feat/session-background-tasks`. Mockup: [design-concept/session-background/index.html](../../../../design-concept/session-background/index.html).

Ana asks Claude to rerun 96 replays. Claude starts them as a background shell, says *I'll compare them when they finish*, and ends its turn. Today `Stop` makes the session **Done**: its row leaves the rows in play and joins the Done group, and the notch flashes it finished. But nothing is done. Claude wakes up by itself when the shell ends, and iTerm2's own Claude Code integration shows the tab as *working · 1 background task running*. ClaudeBar says the opposite of the terminal beside it.

```
 ■■■□□ Claude Code                                            ▾
 1 needs you · 2 working · 3 done
 ─────────────────────────────────────────────────────────────────
 1 ● tinyshop   [Needs you]                              1m 03s
 2 ● airy-poc   [In background]          1 shell         3m 24s     ← turn over, its shell still running
     Gateway provisioning guide steps 3+
 3 ● claudebar  [Working]                                   40s
 3 done ›
```

- **What tells ClaudeBar**: Claude Code's `Stop` hook input carries `background_tasks`, one entry per task still running when the turn ended, each with an `id`, a `type` (`shell`, `subagent`, `monitor`, `workflow`, …), a `status` and a `description`. Claude Code's reference says it is there so a hook can tell *"session is done"* from *"session is paused waiting for background work to wake it back up"*. The hook already sends `Stop`'s whole input; only the parser ignores the field. iTerm2's integration reads the same field.
- **The phase**: a turn that ends with background tasks leaves the session **In background**, not Done. It is in play: it keeps its row, the count line counts it under *working*, and the menu bar glyph shows as for Working. It ranks below Working and above Done.
- **The row**: the badge *In background*, and beside it what is running: *1 shell*, *2 shells*, *1 agent*, or *3 tasks* when they are of several types. In the notch's panel: *1 shell running*.
- **When it ends**: when the work finishes, Claude Code wakes the session for a turn of its own, and that turn's `Stop` comes with no background tasks: the session is Done then, and the notch flashes it finished then, not before. A new prompt from the person makes it Working as any prompt does.
- **What it doesn't change**: a `Stop` without the field (Claude Code from before it, or `StopFailure`) is Done as today. `SubagentStop` carries the same list, scoped to the parent session; it is ignored, as the turn's own `Stop` comes after it. Scheduled wakeups (`session_crons`, from `/loop` and `ScheduleWakeup`) don't count: a session waiting hours for its next loop is Done between them.
- **A task that never ends** (a `monitor` tailing a log) keeps its session In background for as long as it runs. That is true, and iTerm2 says the same.
- **Not here**: the tasks' descriptions or commands in the popover; counting tasks started during a turn (only `Stop` says).

### Laws and owners

| Law | Owner |
|---|---|
| The tasks still running when a turn ended, each with its kind; none for an event that didn't say | `SessionEvent.backgroundTasks` (new) → `[BackgroundTask]?`: `id`, `kind` (`shell`, `agent`, `other`), parsed from `Stop`'s `background_tasks` by `SessionEventParser` |
| A turn that ends with tasks running leaves the session In background; with none, or not said, Done | `ClaudeSession.stop(at:leaving:)`: phase `.inBackground` (new), `backgroundTasks` (new), `finishedAt` nil until Done |
| A session that is working: Working, Agents working, In background | `ClaudeSession.Phase.isWorking` (new); used by the tally, the menu bar glyph and the notch, which each compared phases themselves |
| Order of need: Needs you → Agents working → Working → In background → Done | `SessionMonitor.sessionsByProminence` (exists) |
| How a row words what runs: *1 shell*, *2 agents*, *3 tasks* | `SessionsCardView`, `NotchPanelView`: presentation, from `ClaudeSession.backgroundTasks` |
| The phase's colour: Working's green in the menu bar and the notch; `statusHealthy` in the card | `ClaudeSession.Phase.color` · `AppThemeProvider.color(for:)` |

### Tests

`SessionEventParserTests`: should read the tasks still running when a turn ended · should say nothing of background tasks when the event doesn't · should read no background tasks when none are running.

`ClaudeSessionTests`: should stay in play while its background tasks run · should not count as finished while its tasks run · should be done when its turn ends with none running · should be done when its turn doesn't say what still runs · should work again in the foreground when the person sends a prompt.

`SessionMonitorTests`: should count a session with work in the background as working · should rank work in the background below working and above done · should be done when the turn that work woke ends with none running · should be done when a turn ends in an error.

`NotchActivityResolverTests`: should show a session with work in the background as working, never finished.

`BackgroundWorkTextTests`: should name one kind of work by what it is · should call work of several kinds tasks · should say nothing when no work runs.

## A question Claude asks

**Status:** BUILT on `feat/session-background-tasks`.

Claude asks Ana to choose between three designs (`AskUserQuestion`) and waits. iTerm2's tab says *waiting*; ClaudeBar says **Working** until she answers. ClaudeBar's log for such a session shows only `UserPromptSubmit`, then nothing, while the question was open. *Needs you* is the phase for exactly this, and two things keep it from coming:

- **ClaudeBar never installed `Notification`**: its hook list sits beside `SessionEvent.EventName` and leaves it out (CANONICAL_MODEL's open gap), so a permission prompt shows Working too.
- **A question is no `Notification`**: Claude Code sends one for permission prompts and dialogs, not for `AskUserQuestion`.

- **What tells ClaudeBar**: `PreToolUse` fires as Claude calls the tool, with `tool_name` `AskUserQuestion` and the questions in `tool_input.questions`, each with its `question` text. `PostToolUse` fires once she has answered. iTerm2's integration listens to `PreToolUse` too.
- **The hooks**: the installer registers every `EventName`, each with its matcher: `PreToolUse` and `PostToolUse` match `AskUserQuestion`, so Claude Code calls the hook for that tool only, never for every `Bash` or `Read`; `Notification` matches `permission_prompt|elicitation_dialog`, the prompts that wait on the person, and not `idle_prompt`, which Claude Code sends a minute after a turn ends and would turn a Done session into Needs you; every other event `.*`. Existing installs get them at the next launch, as ClaudeBar reinstalls its hooks when they are on.
- **The phase**: `PreToolUse` for a question makes the session **Needs you**, its prompt the first question's text (*Which design should we build?*), as a permission prompt's is. The notch shows it as it shows a permission prompt. `PostToolUse` makes it Working again.
- **Not here**: plan approval (`ExitPlanMode`), which also waits on the person; whether a `Notification` covers it is not yet checked.

| Law | Owner |
|---|---|
| A question opened, with its text; a question answered | `SessionEvent.EventName` `.preToolUse`, `.postToolUse` (new), `SessionEvent.message` the first question's text, parsed by `SessionEventParser` |
| The hooks: every event ClaudeBar reads, each with its matcher | `HookInstaller`: events from `SessionEvent.EventName.allCases`; `AskUserQuestion` for the tool events, `permission_prompt\|elicitation_dialog` for `Notification`, `.*` for the rest |
| A question opened makes the session Needs you; answered, Working | `SessionMonitor.processEvent` → `awaitInput(_:at:)` · `resume()` (exist) |

`SessionEventParserTests`: should read a question Claude asks · should read a question answered. `SessionMonitorTests`: should need you while Claude waits on its question · should work again once the question is answered. `HookInstallerTests`: should listen to every session event ClaudeBar reads · should call the hook for questions only on tool events · should call the hook for prompts that wait on the person only.

## Phase colours

`ClaudeSession.Phase.color` serves the menu bar glyph and the notch. This change moves two of them:

| Phase | Label | Was | Now |
|---|---|---|---|
| `awaitingInput` | Needs you | yellow | **red**: the one that wants a keystroke, the loudest colour |
| `subagentsWorking` | Agents working | blue | blue |
| `active` | Working | green | green |
| `inBackground` | In background | — | green, as Working (*Work left running in the background*) |
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
