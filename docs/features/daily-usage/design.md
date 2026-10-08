# Daily usage — design

> Applies [the design](../../architecture/ARCHITECTURE.md) to Usage History:
> the words and laws are the model's ([CANONICAL §1, §5](../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them));
> this says how it runs. Users: [README.md](README.md). How duplicates are
> found: [dedup.md](dedup.md). Claude Desktop beside a login:
> [other-apps-design.md](other-apps-design.md).

## 1 · What a person asks, and what is true

A person asks **"how much did I use, day by day?"** *TODAY'S USAGE* (today
against yesterday) and a *Daily token usage — last 30 days* chart (input,
output, cache read and cache write per day, two axes) are **two views of that
one answer**: the last two days, and the last thirty. So the model is a
**series of days**, and a view is a range the page asks for:

```swift
account.usageHistory?.days(in: .last(2))    // TODAY'S USAGE
account.usageHistory?.days(in: .last(30))   // the chart; every date present, empty days included
```

A `Day` is **the sum of its lines**: one line per model, a line holding
what the day holds — tokens by kind and cost (ESTIMATED unless the log
states it) — so a chart can stack by model and still add up to the day.
Records with no model form one unnamed line. Sessions, working time and
cache savings stay the day's own. Nothing about "today and yesterday" is a
type; a range of days is one answer, `Days`, and every view is a question
asked of it — which models, in order; a day's lines, largest first; its
total in a unit.

Today two vendor-named analyzers answer only the last two days, and each one
hard-codes the same five jobs:

| Job | Claude (`ClaudeDailyUsageAnalyzer` + 5 helpers) | Mistral (`VibeSessionLogAnalyzer`) | What it really is |
|---|---|---|---|
| where the records are | `~/.claude/projects/**/*.jsonl`, changed since yesterday | `~/.vibe/logs/session/session_*/meta.json` | a glob |
| how to read one | an assistant line: `message.model`, `message.usage.*`, `timestamp` | `stats.session_total_llm_tokens`, `stats.session_cost`; the time from the folder name, in UTC | a format and field paths |
| which copy counts | `message.id` + `requestId`, the last wins | each file once | an identity |
| what it cost | `ModelPricing` — a Swift table; a local model, or a base URL on this Mac, is free | the log says | a price catalog, or the record's own cost |
| the day | local midnight; a 30-minute pause starts a session | local midnight; a file is a session | one aggregator |

None of these is a vendor's behaviour; each is a value. So, as for usage
(§2), **a tool's usage history is a definition and one engine runs it**: a new
tool's logs, a new model's price or a new view never edit a vendor's Swift
(OCP).

## 2 · The definition: `usageHistory` beside `dataSources`

Record fields use **the mapping's path language** (§3: `$.a.b`, `where`), so
there is one way to point into JSON. Each field names one path; a log that
writes a record more than one way lists its `shapes` (below).

```jsonc
// claude.json
"usageHistory": {
  "records": {
    "files": "${CLAUDE_CONFIG_DIR:-~/.claude}/projects/**/*.jsonl",
    "format": "jsonLines",                       // jsonLines (append-only, read incrementally) · json (one record per file)
    "where": { "path": "$.type", "equals": "assistant" },
    "at": "$.timestamp",                          // ISO 8601
    "id": ["$.message.id", "$.requestId"],        // together its identity: written twice, it counts once — the last wins
    "model": "$.message.model",
    "tokens": {
      "input": "$.message.usage.input_tokens",
      "output": "$.message.usage.output_tokens",
      "cacheWrite": "$.message.usage.cache_creation_input_tokens",
      "cacheWrite1h": "$.message.usage.cache_creation.ephemeral_1h_input_tokens",   // the part kept an hour, priced apart
      "cacheRead": "$.message.usage.cache_read_input_tokens"
    }
  },
  "prices": { "file": "claude-prices.json" },    // a PriceList — or { "service": "AmazonBedrock" }, through PriceCatalog
  "freeWhen": { "localEndpoint": { "file": "${CLAUDE_CONFIG_DIR:-~}/.claude.json",
                                   // the first entry that answers decides; a list is one entry
                                   "url": ["$.env.ANTHROPIC_BASE_URL",
                                           ["$.providers[*].base_url", "$.providers[*].env.ANTHROPIC_BASE_URL"]] } },
  "sessionGap": 1800
},
"accounts": { "patch": { "usageHistory": { "records": { "files": "{{account.configDirectory}}/projects/**/*.jsonl" } } } }
```

```jsonc
// mistral.json
"usageHistory": {
  "records": {
    "files": "~/.vibe/logs/session/session_*/meta.json",
    "format": "json",
    "at": { "fromPath": "session_(\\d{8}_\\d{6})", "format": "yyyyMMdd_HHmmss", "timeZone": "UTC" },
    "tokens": { "total": "$.stats.session_total_llm_tokens" },
    "cost": "$.stats.session_cost"               // the log's own cost wins over any price
  }
}
```

```jsonc
// claude-prices.json — beside the definition; a price change edits this, never Swift
{
  "currency": "USD", "per": 1000000,
  "models": [                                     // exact id first, then the longest prefix
    { "id": "claude-opus-5",   "name": "Claude Opus 5",   "input": "5", "output": "25", "cacheWrite": "6.25", "cacheRead": "0.50" },
    { "id": "claude-sonnet-5", "name": "Claude Sonnet 5", "input": "2", "output": "10", "cacheWrite": "2.50", "cacheRead": "0.20" }
  ],
  "families": [ { "contains": "opus", "as": "claude-opus-4-6" }, { "contains": "haiku", "as": "claude-haiku-4-5-20251001" } ],
  "free": [ "qwen", "llama", "gemma", "mistral", "gpt-oss", "ollama" ],   // a model of a local family costs nothing
  "otherwise": { "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" }
}
```

- **One price shape, two origins.** A price file is data, decoded into a
  `PriceList` that holds the rules: exact id → the longest prefix (either
  way round) → a family → a free family → `freeWhen` → `otherwise`. A cloud's
  price list (`{ "service": … }`) is fetched through the `PriceCatalog` port
  Bedrock uses (#417) into the same `PriceList`. A tool that writes its own
  cost needs neither.
- **Per login, like data sources.** The default login reads `usageHistory`; an
  added login gets `accounts.patch.usageHistory` merged in and its values filled
  (`{{account.configDirectory}}`), so an added Claude login has its own
  usage history for the first time. A definition without `usageHistory` has none.
- **Money stays exact.** Prices are decimal texts; cost is
  tokens × price ÷ `per` in `Decimal`, shown as an estimate unless the record
  gave its own `cost`.
- **`freeWhen.localEndpoint`** replaces `ClaudeLocalInferenceDetector`: a
  base URL in that file on a loopback host (`localhost`, `127.0.0.1`, `::1`,
  `0.0.0.0`, `*.localhost`) makes an unpriced model free. It describes the
  route **now**, so it prices only the day that holds now; an earlier day
  keeps its estimate — over-reporting is the safe direction.

#### When logs differ: one record, three tiers

Tools write their logs differently. The difference stays at the edge: every
reader turns its file into the same **`LogRecord`** — `at`, `id`, `model`,
`tokens` (input · output · cache write · cache read, or a `total`), `cost` —
and everything after it (dedupe, days, sessions, prices, the ledger, the
screens) never learns which tool wrote it.

| How a tool's logs differ | What a contributor changes | Swift? |
|---|---|---|
| where the files are, what a field is called (Claude's `message.usage.input_tokens`, Vibe's `stats.session_total_llm_tokens`) | `files` and the field paths | no |
| the same idea, said another way: the time in a folder's name, the log's own cost, a session per file, a running total | an option: `at.fromPath`, `cost`, no `sessionGap`, `"cumulative": true` | no |
| one log that writes a record more than one way (Oh My Pi's turns under `message.usage`, the side calls it logs under `usage`) | `records.shapes`: one entry per shape, each read whole — its own `where`, `at`, `id` and paths | no |
| a record no path can say (a field to compute, a list to add up) | `"script": "x-log.js"` — `read(record, context)` returns one `LogRecord`, the escape hatch a mapping already has (built when a tool first needs it) | no |
| a file of another kind (SQLite, binary) | a new `format` case and its reader, named for the format, with a test that names no tool | once |

**A script, by example.** Say a tool logs one line per turn, in an
OpenAI-style shape no path can turn into a record: the time in epoch
milliseconds, cached tokens *included* in the input count, and one usage
entry per model in a list.

```jsonc
// a line of ~/.example/history/2026-10-03.jsonl
{"kind":"turn","ts":1759500000123,"turn":"t_81","usage":[
  {"model":"gpt-5","prompt_tokens":12000,"cached_tokens":9000,"completion_tokens":800},
  {"model":"gpt-5-mini","prompt_tokens":3000,"cached_tokens":0,"completion_tokens":200}]}
```

The definition keeps what paths can say — the files, the format, the
filter — and hands each record to a script instead of naming its fields:

```jsonc
// example.json
"usageHistory": {
  "records": {
    "files": "~/.example/history/*.jsonl",
    "format": "jsonLines",
    "where": { "path": "$.kind", "equals": "turn" },   // still the byte prefilter: the script sees only these
    "script": "example-log.js"                         // in place of at · id · model · tokens · cost
  },
  "prices": { "file": "example-prices.json" },
  "sessionGap": 1800
}
```

```js
// example-log.js — read(record, context) → a LogRecord, a list of them, or null to skip
function read(record, context) {
  if (!Array.isArray(record.usage)) return null;
  return record.usage.map(function (u, i) {
    return {
      at: record.ts / 1000,                          // epoch seconds
      id: record.turn + "#" + i,                     // one record per model in the turn
      model: u.model,
      tokens: {
        input: u.prompt_tokens - u.cached_tokens,    // the log counts cached tokens as input
        cacheRead: u.cached_tokens,
        output: u.completion_tokens
      }
      // cost: "0.0123" — when the log states it; a decimal text stays exact
    };
  });
}
```

That line becomes two records — `gpt-5` with 3,000 input, 9,000 cache read
and 800 output tokens, `gpt-5-mini` with 3,000 and 200 — priced, deduped and
summed into days exactly like Claude's. The rules are a mapping script's
(§2): it runs in JavaScriptCore with no file, network or process access;
`context` holds `now`, `timeZone`, the file's `path` and the definition's
`values`; money helpers (`jsonDecimal`, `decimalAdd`) keep a stated cost
exact; and it turns one record into records, nothing else. A script is
slower than paths, so `where` filters first, and a tool whose fields paths
*can* reach never needs one.

**Neither Claude nor Mistral uses a script**, and the script tier is not
built with them. Claude's logs are paths plus options (`where`, a composite
`id`, `sessionGap`, `freeWhen`), and they run to gigabytes: a JavaScriptCore
call per line would undo the incremental reader and the byte prefilter.
Mistral's one tool-shaped fact — the time in the folder's name — is a
common one (logs rotated by date), so it is an option, `at.fromPath`, that
any tool can use. The rule for choosing: **an idea several tools share is
an option; an idea only one tool has is a script.**

`format` is a closed sum like `Fetch`: the engine stays closed, a new tool is
data. The reading rules every format shares:

- **`files`** is a glob: `**` any depth, `*` within one name; hidden files
  are skipped, and only files changed since the range's first day are read.
- **`where`** keeps the records that match. Its text is also a byte
  prefilter: a line holding no shape's `where` text is never decoded. A shape
  without a `where`, or with one that isn't text, turns the prefilter off.
- A record without `at`, or without a declared `model`, is skipped; so is
  one where no token field and no `cost` answers — it says nothing about
  usage (Claude's assistant line without `usage`, a Vibe `meta.json`
  without `stats`). Otherwise a missing token field counts 0.
- **`id`**'s paths together are a record's identity; a record missing any of
  them is never merged with another.
- **`records` is the log**: `files` and `format`, then the record's shape —
  `where`, `at`, `id`, `model`, `tokens`, `cost` — or, when the log writes a
  record more than one way, a list of **`shapes`**; never both. Each file is
  read once, and a line is read whole by the first shape whose `where`
  holds: one shape's paths never answer for another's record. Every shape in
  a list has a `where`, so none silently takes another's lines. `id` dedupe
  runs over all of the log's records, whatever their shape. Without `shapes`
  a definition is written back exactly as before, so its fingerprint and its
  kept days stay put.

**One record, written two ways.** Oh My Pi writes a turn's usage under the
message, and a model call it makes outside the conversation (memory,
judgment, an advisor) as a `model_usage` entry with `usage` at the top. To
the person both are the same thing — a model call that spent tokens and
money — so it is one record in two shapes:

```jsonc
// omp.json
"records": {
  "files": "${PI_CODING_AGENT_DIR:-~/.omp/agent}/sessions/**/*.jsonl",
  "format": "jsonLines",
  "shapes": [
    { "where": { "path": "$.message.role", "equals": "assistant" },
      "at": "$.timestamp", "id": ["$.id", "$.timestamp"],
      "tokens": { "input": "$.message.usage.input", "output": "$.message.usage.output",
                  "cacheWrite": "$.message.usage.cacheWrite", "cacheRead": "$.message.usage.cacheRead" },
      "cost": "$.message.usage.cost.total" },
    { "where": { "path": "$.type", "equals": "model_usage" },
      "at": "$.timestamp", "id": ["$.id", "$.timestamp"],
      "tokens": { "input": "$.usage.input", "output": "$.usage.output",
                  "cacheWrite": "$.usage.cacheWrite", "cacheRead": "$.usage.cacheRead" },
      "cost": "$.usage.cost.total" }
  ]
}
```

Files and format describe the log; paths and filters describe a shape. So an
added login's `accounts.patch.usageHistory` moves the log —
`{ "records": { "files": "…" } }` — and keeps its shapes, since a merge patch
leaves the keys it doesn't name. Left out on purpose: shapes in different
files are different logs, not another shape (a list of logs, added when a
tool needs one), and shapes don't inherit shared fields — omp repeats `at`
and `id`, and each shape reads on its own.

**Other apps.** `usageHistory.otherApps` lists apps on this Mac that use
the same plan and keep their own count, each `{label, records, prices?}`:
Claude Desktop's `buddy-tokens.json` is `format: json`, `tokens.total`, and
`at: {"field": "$.tokens-today.date", "format": "yyyy-MM-dd"}` — a field read
with a format, local unless it names a `timeZone`. Each is its own
`UsageHistory` with its own ledger key (`<login>/<label>`), shown as its own
card, never summed with the login's days; without prices it has tokens and
no cost. An added login's patch sets `otherApps` to `null`. A token count that
is negative or not whole drops the record. Design:
[other-apps-design.md](other-apps-design.md).

## 3 · Thirty days without re-reading thirty days: the ledger

Claude's logs run to gigabytes; re-reading thirty days on every popover open
is not an option, and today's in-memory cache only covers two. The day is the
natural unit to keep:

- **A day closes** a fixed while after its midnight (late lines from a
  session that ran past midnight still land). A closed day is summed once
  and kept in a **`DayLedger`** — per login, one small JSON file under
  `~/.claudebar/usage-history/`, a few hundred bytes a day.
- **Open days** (today, and yesterday until it closes) are read from the logs
  every time — incrementally, as today, so a popover open reads only what
  was appended.
- **Dedupe stays exact**: a record's identity only has to be remembered
  while its day is open.
- **A ledger is a cache, not a record**: deleting it re-reads the logs; a
  change to the definition (`usageHistory` or the prices), or to how days
  are summed — both carried in the log's fingerprint — invalidates it.

## 4 · Where it lives: the login owns it, `DataSources` extracts it

**No new module.** A module earns its place with its own SDK, a second
consumer, or a boundary the build must enforce; usage history has none —
`Providers` is its only consumer, and the work it needs (find files, read
JSON with the path language, expand `~`, price tokens) is what `DataSources`
already does behind `internal`. So it splits along the line every provider
already has:

- **The login owns it.** `Account` holds `usageHistory: UsageHistory?` —
  `nil` when the definition has no `usageHistory` — and `UsageHistory`
  (in `Providers`) answers `days(in:)` from its `DayLedger` of closed days,
  asking its log for the open ones. A page reads
  `account.usageHistory?.days(in:)` (CANONICAL §2.1), never a dictionary
  keyed by provider ids, and there is no app-wide registry.
- **`DataSources` extracts it** — the only part that differs per provider.
  The definition's `usageHistory` decodes as a `UsageLog.Definition` (as
  `dataSources` decode as `DataSourceDefinition`); `DataSources.makeUsageLog`
  fills it with the login's values and returns a `UsageLog` whose
  `days(from:to:)` reads and prices the records. Its readers and aggregator
  are `internal` workers beside `FileFetcher` and `JSONMapper`.
- **`Day` is a kernel value** in `Quotas`, beside `Cost` and `CostLine`,
  replacing `DailyUsageReport`/`Stat`, which already live there.

Not in `Provider`'s refresh: usage history is not a meter and is read on its
own cadence (popover open, never the background poll).

| Piece | Job | From today's |
|---|---|---|
| `UsageLog.Definition` (`DataSources`) | the JSON, `Codable`, no behaviour | the constants in both analyzers |
| `UsageLog` (`DataSources`) | `days(from:to:)`: the readers, prices and aggregator for one login | both analyzers' entry points |
| `JSONLinesReader` (`DataSources/Internal`) | one record per line a shape picks out; reads only what was appended since the last scan, re-reads a file that changed under it; a byte prefilter from the shapes' `where` texts | `SessionJSONLParser` + `SessionLogCache`, generalised |
| `JSONLogReader` (`DataSources/Internal`) | one record per file, by the same first-matching-shape rule; `at.fromPath` reads the time from the path | `VibeSessionLogAnalyzer.loadSessions` |
| `RecordShape` (`DataSources/Internal`) | one per shape: whether its `where` holds, and the record read whole from its paths; the first shape whose `where` holds reads a line | — (new) |
| `LogRecord` (`DataSources/Internal`) | the one form every reader produces | `TokenUsageRecord`, `ParsedSession` |
| `PriceList` (`DataSources/Internal`) | the record's own cost, else the list (exact → longest prefix → family → free → `freeWhen` → otherwise); cache savings | `ModelPricing` |
| `LocalEndpoint` (`DataSources/Internal`) | `freeWhen.localEndpoint`: is the route in that file on this Mac? | `ClaudeLocalInferenceDetector` |
| `LogFileFinder` (`DataSources/Internal`) | `files`' glob, changed since a date | `findRecentJSONLFiles` |
| `DayAggregator` (`DataSources/Internal`) | dedupe by `id` (last wins), split by local day, sessions by `sessionGap` (a record is a session without one), working time, cache savings, a cost line per model | both analyzers' `aggregate` |
| `DayLedger` (`Providers/Internal`) | closed days kept per login; open days asked of the `UsageLog` | — (new) |
| `UsageHistory` (`Providers`, @Observable, one per login) | `days(in:)`, every date present | `Domain/UsageHistory` (one object for all logins, two days only) |
| `Day` (`Quotas`) | the answer — the sum of its lines, one per model; records with no model, one unnamed line; `DailyUsageStat` until the words land | `Quotas` |
| `Days` (`Quotas`) | a range of days: which models in order, a day's lines largest first, its total in a unit | — (new; the chart's arithmetic moves here) |

A model's display name is a mechanical rule, no vendor named: drop a
leading segment when at least two remain (`claude-opus-4-6` reads
*opus-4-6*), a trailing `-YYYYMMDD` date, and a trailing `:<size>`
(`qwen3-coder:30b` reads *qwen3-coder*). It lives on the line, beside the
other formatted strings.

Ports: the ledger's store (a `@Mockable` `LedgerStore`) in `Providers`, and
`PriceCatalog` for a cloud's prices. **The log files are not a port**: the
readers' whole job is bytes on disk (offsets, inodes, half-written lines), so
they are tested on files in a temporary folder, as credential files already
are; a mock would test nothing they do. No module names
a vendor; the readers are named for formats. The page owns the views:
*TODAY'S USAGE* cards read `days(in: .last(2))`, a chart reads
`days(in: .last(30))` and makes two choices — what is counted (cost,
tokens, cache) and how the bars split (by kind, or by model) — and
renders what `Days` answers.

## 5 · Is it easy to change? The checks

| A person or a contributor wants… | They change |
|---|---|
| a *Last 30 days* chart, a week view, a month total | the page only: another range of `days` |
| a new model's price, or a price cut | `claude-prices.json` |
| *TODAY'S USAGE* for another tool that logs JSON | that tool's definition: a `usageHistory` block |
| Codex's usage history (`~/.codex/sessions/**/rollout-*.jsonl`, whose `token_count` events carry a session's **running total**) | `codex.json`'s `usageHistory`, plus one reader option, `"cumulative": true` (the last record per session counts), with a neutral test |
| Oh My Pi's usage history (turns, subagents and side calls in `~/.omp/agent/sessions/**/*.jsonl`, copied whole into forked sessions) | `omp.json`'s `usageHistory`: one log, two `shapes`, and `id: [$.id, $.timestamp]` — the identity omp's own stats use for fork copies |
| a binary log format | one new reader, named for the format |
| an added login's own usage history | nothing: `accounts.patch.usageHistory` |

## 6 · Guest passes stay Swift

**Guest passes** (`ClaudeGuestPassSource`: `claude /passes` in a terminal,
the referral link from the screen or the clipboard, an optional count) are
**not** a definition block. Only one product has them: a `guestPasses` key
in the shared definition, with a `clipboard` option on every `cli` fetch,
would put one vendor's feature into the format every provider uses —
speculative generality, the opposite of OCP. The rule that decides it is the
one for log shapes (§2): *an idea several providers share is data; an
idea only one product has stays at the edge.*

So the capability is generic and its one source is Claude's: `GuestPasses`
and the `@Mockable` `GuestPassSource` port live in `Providers`;
`ClaudeGuestPassSource` is handed in by the App for Claude and reached as
`account.guestPasses` (the default login's). It is the last file in
`Infrastructure/Claude`, and moves to the App when `Infrastructure` is
carved — the composition root is where a vendor may be named. If a second
product ever offers passes or referrals, that is the moment to make it data.
