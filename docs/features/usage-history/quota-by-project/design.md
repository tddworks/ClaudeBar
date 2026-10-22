# Quota by project — design

> Applies [the design](../../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §5](../../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). The days it reads, and
> how a login's logs become them: [daily-usage](../daily-usage/design.md).
> The values it reuses — `Days`, and `ModelMix` as the shape it mirrors:
> [insights](../insights/design.md).

> **Status: BUILT** (Claude Code only, see §7). Mockup:
> [design-concept/quota-by-project](../../../../design-concept/quota-by-project/index.html).

## 1 · What a person asks, and what is true

Tom ([USER_JOURNEYS §1](../../../architecture/USER_JOURNEYS.md)) asks **"what
did I use, day by day?"** — and the insights answered *which models* he leans
on and *how his year looked*. The next question he asks while staring at a
month of usage is **"where did all that work go?"** — which projects, which
folders, did `marron` really eat the week?

The answer has to come from the usage the app already reads, not from a second
tracking system. Today, per login:

- A recorded **day** (`DailyUsageStat`, kept by the `DayLedger` in
  `~/.claudebar/usage-history/<login>.json`) carries its date, its tokens by
  kind, its cost, its working time, its sessions — and `lines`, one line per
  model. **It names no project.**
- A **record** (`LogRecord`, the reader's one shape, not persisted) carries a
  time, an identity, a model, tokens by kind and a cost. **It names no
  project either.**
- The **raw logs do**. Claude Code writes the working directory (`cwd`) on
  every assistant line it appends to `~/.claude/projects/**/*.jsonl`; the
  definition's shape simply never read it. The insights design said exactly
  this was the missing piece ([insights §6](../insights/design.md)): *a log
  may name a model and a request, not a repo … until a definition can say
  which repo this record is, the question is left out rather than guessed.*

So the feature is the two halves that design deferred, each its own small
thing: **one word in the mapping's path language** so a definition can say
*which field holds the working directory*, and **one value over `Days`** that
answers the question the moment the days carry it.

```swift
let year = account.usageHistory?.lastYear          // the range, as the insights read it
let unit = year.defaultUnit                        // the view's one choice
ByProject(of: year, in: unit).parts                // "where did my usage go"
```

## 2 · The words

| Word | Means | Not |
|---|---|---|
| a **project** | the working directory a record was spent in, named by its last path component — *marron*, *api* | an absolute path (never stored, never rendered); a git repo by name |
| a record's **project** | what the shape's `project` field reads — the raw directory; a record whose log writes none is **unnamed** | inferred from a file path or a prompt |
| a day's **project lines** | one line per project, what that project's records spent — the day's project split | a second day total |
| the **by-project** read | each project summed over a range, largest first, the unnamed part among them so the parts add up | a kept report; a quota |
| a **part** | one project's value in the unit, and its share of the range | a login: the read stays one login's own, as every Usage History read is |
| the **top project** | the largest *named* one — never the unnamed part | necessarily the one the person calls their main project |

A project is **named at aggregation, once**: the last path component of the
working directory, so the ledger holds *marron*, never
`/Users/you/orca/workspaces/ClaudeBar/marron`. Two directories that share a
last component read as one project — the honest price of a name a person can
read; the unnamed part is the records whose log wrote no directory at all.

## 3 · The model

```
the log's line ──► UsageLog.Shape.project    the one new word: the field of the working directory   DataSources
      │
      ▼
LogRecord.project? ──► DayAggregator         names it (ProjectUsageLine.name(of:)) and tallies the
      │                                      day's project split, one line per project
      ▼
DailyUsageStat.projects: [ProjectUsageLine]  the day's split, kept with the day (the ledger's)
      │
Days (projects · hasProjects · value(of:in:))  the range answers, as it does for models
      │
      └─► ByProject(of: days, in: unit)      parts: [Part]   Part = line · value · share   · top

ProjectUsageLine + ProjectUsageLine          a line owns its own sum
```

| Type | Answers | Where |
|---|---|---|
| `UsageLog.Shape.project` | the field a log writes the record's working directory in — one optional path, read like `model` | `Modules/DataSources/Sources/UsageLog.swift` |
| `LogRecord.project` | the record's raw directory, as the reader found it | `Modules/DataSources/Sources/Internal/Logs/LogRecord.swift` |
| `ProjectUsageLine` | one project's share of a day: its tokens by kind and cost; its **name** — the last path component of the directory; `+` | `Modules/Quotas/Sources/ProjectUsageLine.swift` |
| `DailyUsageStat.projects` | the day's split, one line per project, unnamed last — decoded empty from days kept before | `Modules/Quotas/Sources/DailyUsageStat.swift` |
| `Days.projects` · `hasProjects` · `value(of:in:)` | the range's named projects in order; whether any day names one; a project line's value in a unit | `Modules/Quotas/Sources/Days.swift` |
| `ByProject` | each project summed over the range, largest first in a unit, each part with its share; `top` | `Modules/Quotas/Sources/ByProject.swift` |
| `UsageSection.projectMix` | whether the popover shows the projects card — hidden until the person shows it, and it reads the year | `Sources/Domain/Settings/UsageSection.swift` |
| `ProjectMixView` | the split as one bar and a row per project, largest first | `Sources/App/UsageHistory/` |

**A day carries a split only when its log names projects.** A day none of
whose records names a directory carries no project lines at all — not an
empty-named one — so the ledgers of the providers that don't capture stay as
they were. On a day that *does*, the records without a directory form one
unnamed part, so the parts add up to the day exactly as a day's model lines
do ([insights §2](../insights/design.md)); and a day that names none, inside
a range that names one, is the unnamed part of the range — `ByProject` reads
it in, so the parts add up to the range and no project's share overstates.

## 4 · The laws, each with one owner

| Law | Owner |
|---|---|
| a log's record may name its project — the field that holds the working directory — read like the model, one more word in the shape's path language | `UsageLog.Shape` |
| a record's project is named once, at aggregation: the last path component of the working directory; a path that names no component names itself; a record that names nothing is unnamed | `ProjectUsageLine.name(of:)` · `DayAggregator` |
| a day's project split is one line per project — named lines in name order, the unnamed part last — and exists only when the day's records name at least one project | `DayAggregator` · `DailyUsageStat.projects` |
| two lines of one project add up to one line: every count and the cost | `ProjectUsageLine` (`+`) |
| the by-project read is each project summed over the range, largest first, ties by name, the unnamed part included so the parts add up; each part carries its share; the top project is the largest named one, never the unnamed part | `ByProject` |
| a range answers whether any day names a project, and a project line's value in a unit — the same questions it answers for models | `Days` |
| an absolute working directory is never kept or shown: the ledger holds project lines under their last component | `ProjectUsageLine` (naming at aggregation) |
| whether the projects card shows is the person's section choice, hidden until shown, and it reads the year only while a year section is on | `UsageSection.projectMix` |
| a project keeps its colour between views of one range — the one palette, by the project's place among the range's projects; the unnamed part is grey | `ModelColors` (App) |

## 5 · The pieces

| Piece | Job | Where |
|---|---|---|
| `UsageLog.Shape.project`, `LogRecord.project`, `DayAggregator`'s split | the capture: a definition's word, the record's raw directory, the day's split | `Modules/DataSources/Sources/` |
| `ProjectUsageLine`, `ByProject`, `Days`' reads | the kernel values, siblings of the model line and the mix | `Modules/Quotas/Sources/` |
| `claude.json`'s `"project": "$.cwd"` | Claude Code attributes its records — the one provider whose log writes the directory on every line it reads | `Modules/Providers/Resources/Providers/` |
| `UsageSection.projectMix`, the settings switch | the person's choice, hidden by default beside *Model mix* | `Sources/Domain/Settings/`, `Sources/Infrastructure/Settings/` |
| `ProjectMixView`, `ModelColors` | the card and the palette it reads | `Sources/App/UsageHistory/` |

The card sits in the popover's usage area beside the heatmap and the model
mix, reads the same `lastYear` they read, and shows only when the range names
a project (`Days.hasProjects`) — a provider whose log writes no directory
shows no card rather than a split of one unnamed part. The heading is the
page's to word, as the mix's is.

## 6 · Is it easy to change?

| A person or a contributor wants… | They change |
|---|---|
| another tool to attribute its projects | its definition's shape gains `"project": "<field>"` — no Swift, when its log writes the directory on the records it reads |
| a different range (this week, last month) | the page: the card's `days` and its heading — `ByProject` reads whatever `Days` it is given |
| a project's part in the weekly recap | a `Recap` read built on the same value, once more than one provider captures (§7) |
| a longer or shorter name (two components, a tilde) | `ProjectUsageLine.name(of:)` — the one place |
| per-session attribution | the same shape grows the same way, named for the session — deliberately out (§7) |

## 7 · Considered, rejected, and deferred

- **A second tracking system** (ClaudeBar watches `git` or the terminal's
  cwd). Rejected: the logs already hold the answer for the tool that matters;
  the shape's one word is the whole of the capture.
- **Naming in the reader** (the reader emits names, not paths). Rejected: the
  naming is aggregation's decision, so it is tested once and the reader stays
  a dumb pipe; `LogRecord` carries what the log wrote.
- **Inferring the project from the log's folder** (`~/.claude/projects/`
  mangles the path: `-Users-wenbiao-zheng--claude`). Rejected: the record's
  own `cwd` is exact and needs no unmangling.
- **Other providers' capture — deferred.** Codex writes its directory on a
  `session_meta` record, not the `token_count` lines the shape reads; OpenCode
  keeps it in its sessions table, outside the row query; Mistral's meta
  writes none. Each gains the split by extending its own definition once its
  reader can answer the field — the field is already general. Until then the
  honest answer is one provider's split and an unnamed part everywhere else,
  which is why the **weekly recap's** project part is deferred with them: a
  cross-provider split today would read as more truth than it has.
- **Windows paths.** A definition that reads a Windows directory splits on
  `/` only; a tool that writes `\` gets the whole path as one name until its
  definition or this function learns it. Claude Code writes `/` everywhere.
