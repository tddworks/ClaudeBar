# Daily Usage Token/Cost Deduplication — Calculation Logic Design

**Status:** Implemented
**Date:** 2026-06-09
**Issue:** [#207](https://github.com/tddworks/ClaudeBar/issues/207) — Daily Usage cost & token cards overcount ~4×
**Follow-up:** [#190](https://github.com/tddworks/ClaudeBar/issues/190) — locally served models billed at Anthropic rates (§11)
**Affected code:** `Sources/Infrastructure/Claude/SessionJSONLParser.swift`, `Sources/Infrastructure/Claude/ClaudeDailyUsageAnalyzer.swift`, `Sources/Infrastructure/Claude/ModelPricing.swift`, `Sources/Infrastructure/Claude/ClaudeLocalInferenceDetector.swift`

---

## 1. Problem

The Daily Usage cards (Cost Usage / Token Usage) sum **every** usage-bearing line in
`~/.claude/projects/**/*.jsonl`. Claude Code writes the **same** `message.usage` block
multiple times:

1. **Streaming** — one assistant line per content block as the response streams
   (thinking / text / tool_use). Each repeats the full `usage`; `output_tokens` grows
   across the snapshots until the final, complete value.
2. **Parallel tool calls** — multiple assistant messages in one turn share the same
   `message.id` with byte-identical `usage`.
3. **Resume / branch** — when a session is resumed or branched, prior entries are copied
   into the new session file, so identical lines recur across different `.jsonl` files.

Today's pipeline (`SessionJSONLParser` → `ClaudeDailyUsageAnalyzer.aggregate`) creates one
`TokenUsageRecord` per line and adds them all together, with **no deduplication**. Result:
the displayed cost and token totals are inflated.

### Measured impact (this machine, all history)

| Metric | Value |
|---|---|
| distinct `(message.id, requestId)` groups | 12,297 |
| groups appearing more than once | 6,780 (55%) |
| duplicate groups with **byte-identical** usage | 6,437 |
| duplicate groups with **varying** `output_tokens` (streaming) | 343 |
| naive sum (current app) | 5,357,322,061 tokens |
| deduped (last-wins) | 3,027,710,023 tokens → **1.77× reduction** |

Cache-heavy days reach ~4× (per the issue), because duplication multiplies the
already-dominant cache-read figure.

### Confirmed against Anthropic's own guidance

[Agent SDK — Track cost and usage](https://code.claude.com/docs/en/agent-sdk/cost-tracking):

> "When Claude uses multiple tools in one turn, all messages in that turn share the same
> ID, so **deduplicate by ID to avoid double-counting**."
>
> "**Use the highest value: the final message in a group typically contains the accurate
> total.**" (output-token discrepancy resolution)

The doc's own example keeps a `seenIds` set and counts each message ID once — exactly the
step we are missing.

---

## 2. Goals & Non-Goals

**Goals**
- Eliminate over-counting so Cost/Token cards align with Claude Code's own `/cost`.
- Handle all three duplication sources (streaming, parallel tools, resume/branch copies).
- Preserve correctness for the streaming case: never under-count `output_tokens`.
- Keep the change localized to the parse → aggregate path; no UI/domain-model churn.

**Non-Goals**
- Authoritative billing. The cost figure remains a **client-side estimate** built from a
  local price table; it can drift from the real bill (pricing changes, unknown models).
  This matches the SDK's own warning. We target parity with `/cost`, not the invoice.
- Changing the 2-day scan window, working-time estimation, or per-model pricing tables.

---

## 3. Deduplication Key

**Chosen key:** `(message.id, requestId)` — composite.

| Option | Behavior | Decision |
|---|---|---|
| `message.id` alone | What the SDK doc documents as the minimum. | Sufficient in practice. |
| `(message.id, requestId)` | What ccusage uses; collapses only when **both** match. | **Chosen** — superset-safe. |

On real data the two are **identical**: no `message.id` maps to more than one `requestId`
(verified: 12,300 distinct under either key). We choose the composite because:

- It matches the established reference implementation (ccusage), easing cross-checking.
- It is strictly safer: if a future Claude Code format ever reused an ID across requests,
  the composite keeps them separate rather than silently merging.

**Both fields are top-level/nested-present** in real logs:
- `requestId` — top-level line field (e.g. `req_011Cax…`)
- `message.id` — nested in `message` (e.g. `msg_01Dso…`)

### Missing-key fallback

A line lacking **either** key cannot be safely grouped. Such a record is treated as
**its own unique group** (keyed by a per-record sentinel) and counted as-is. This is
conservative: it never merges records that might be distinct, at the cost of possibly
retaining a genuine duplicate that happens to lack keys (not observed in practice).

---

## 4. Collapse Rule: Last-Wins

Within a `(message.id, requestId)` group, keep **one** record:

> **Last occurrence in file order wins.**

Rationale, from the data and the SDK doc:

- Streaming snapshots accumulate `output_tokens` (`1 → 248`), so the **final** line holds
  the complete, billed value.
- Empirically, `last-wins == max-wins` on this machine (both 3,027,710,023). Last-wins is
  the simpler rule and matches the doc's "final message in a group."
- `first-wins` would **under-count** the 343 streaming groups → rejected.

Because input / cache_creation / cache_read are stable across a group's snapshots while
only `output_tokens` grows, taking the whole last record (not a field-wise max) is correct
and simplest.

### Ordering guarantee

Records are emitted in file-read order, and files are processed deterministically. Last-wins
relies only on per-file line order, which preserves streaming sequence (the final snapshot
is physically last in the file). Cross-file copies (resume/branch) are byte-identical for
the stable fields, so which file "wins" is immaterial.

---

## 5. Algorithm

```
parse:   for each assistant line with usage:
             emit TokenUsageRecord{ messageId, requestId, model,
                                    input, output, cacheCreation, cacheRead, timestamp }

analyze: allRecords = parse(all recent jsonl files)        // unchanged
         deduped    = collapseLastWins(allRecords)          // NEW
         partition deduped into today / yesterday by timestamp
         aggregate(today), aggregate(yesterday)             // unchanged math
```

### `collapseLastWins`

```swift
// Keep the last record seen per (messageId, requestId).
// Records missing either key are kept as-is (unique sentinel key).
func collapseLastWins(_ records: [TokenUsageRecord]) -> [TokenUsageRecord] {
    var lastByKey: [DedupKey: TokenUsageRecord] = [:]
    var order: [DedupKey] = []          // preserve first-seen order for stable output
    var sentinel = 0

    for record in records {
        let key: DedupKey
        if let id = record.messageId, let req = record.requestId {
            key = .composite(id, req)
        } else {
            key = .unkeyed(sentinel); sentinel += 1
        }
        if lastByKey[key] == nil { order.append(key) }
        lastByKey[key] = record       // last-wins overwrite
    }
    return order.map { lastByKey[$0]! }
}

enum DedupKey: Hashable {
    case composite(String, String)
    case unkeyed(Int)
}
```

**Where it runs:** in `ClaudeDailyUsageAnalyzer.analyzeToday()`, on the combined
`allRecords` array **before** today/yesterday partitioning — so duplicates split across
files (resume/branch) collapse globally, not just within one file.

**Complexity:** O(n) time, O(n) space over assistant lines in the 2-day window. Negligible
vs. existing file I/O.

---

## 6. Data Model Change

`TokenUsageRecord` gains two optional identity fields:

```swift
struct TokenUsageRecord: Sendable, Equatable {
    let messageId: String?      // NEW — message.id  (e.g. "msg_01Dso…")
    let requestId: String?      // NEW — top-level requestId (e.g. "req_011Cax…")
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let timestamp: Date
    var totalTokens: Int { inputTokens + outputTokens }
}
```

`SessionJSONLParser` reads `json["requestId"]` and `message["id"]` (both `as? String`),
defaulting to `nil` when absent. Both `parse(fileURL:)` and `parse(content:)` paths are
updated identically.

> The aggregation math in `aggregate(records:date:)` is **unchanged**. It simply receives a
> deduplicated array. Working-time / session-count estimation also benefits, since it no
> longer sees repeated timestamps.

---

## 7. Worked Example

Input lines for one response (streaming), plus one resume-copy in another file:

```
file A: msg_01X / req_9  in=7 out=1   cc=2499 cr=46316   t=10:00:00.1
file A: msg_01X / req_9  in=7 out=1   cc=2499 cr=46316   t=10:00:00.2
file A: msg_01X / req_9  in=7 out=248 cc=2499 cr=46316   t=10:00:00.9   ← final
file B: msg_01X / req_9  in=7 out=248 cc=2499 cr=46316   t=10:00:00.9   ← resume copy
```

- **Today (naive):** counts all 4 → output 1+1+248+248 = 498, totals ~4× inflated.
- **Today (last-wins):** one record kept → `in=7 out=248 cc=2499 cr=46316`. Correct,
  matches `/cost`.

---

## 8. Test Plan (Chicago-School, state-based)

Fixtures live as inline JSONL strings fed to `SessionJSONLParser.parse(content:)` and a
`ClaudeDailyUsageAnalyzer` with injected `now` and a temp `claudeDir`.

| # | Scenario | Assert |
|---|---|---|
| 1 | Parser captures `messageId` + `requestId` from a real-shaped line | fields populated |
| 2 | 3 byte-identical lines, same `(id,req)` | aggregate counts once |
| 3 | Streaming: output grows `1 → 248`, same `(id,req)` | keeps `output=248` (last/max) |
| 4 | Same `(id,req)` duplicated across **two files** (resume) | counts once globally |
| 5 | Two **distinct** responses (different ids) | both counted, no merge |
| 6 | Line missing `requestId` (or `id`) | kept as-is, not merged with others |
| 7 | Regression: known fixture → expected deduped cost/token totals | exact match |
| 8 | Working-time/session-count unaffected by dedup of same-timestamp dups | stable value |

Run: `xcodebuild test -scheme ClaudeBar-Workspace -workspace ClaudeBar.xcworkspace
-destination 'platform=macOS,arch=arm64'` (bypass Tuist test caching).

---

## 9. Rollout & Risk

- **Backward compatible:** new fields are optional; older lines without IDs still parse
  (counted as-is via the fallback).
- **User-visible effect:** Cost/Token cards drop to ~1/1.8–4× of prior values. This is the
  *correct* number, but it is a visible decrease — note it in the CHANGELOG so users don't
  read it as data loss. Frame as "Daily Usage now deduplicates streamed/duplicate session
  entries to match `claude /cost`."
- **No migration:** stateless recompute on next scan.
- **Estimate caveat:** cost remains a local estimate (price table); keep any "≈"/estimate
  affordance in the card copy if present.

---

## 10. Alternatives Considered

| Alternative | Why not |
|---|---|
| Dedup by `message.id` only | Equivalent on current data; composite is safer and matches ccusage. Acceptable fallback if `requestId` is ever absent project-wide. |
| First-wins / first-seen | Under-counts streaming groups' `output_tokens`. |
| Field-wise max across group | Equivalent to last-wins here but more code; only needed if stable fields ever varied (they don't). |
| Dedup inside each file only | Misses resume/branch copies that span files. Must dedup on the combined set. |
| Switch to an authoritative usage source (à la tokemon's OAuth path) | Larger, orthogonal change; doesn't block fixing the inflation. Possible future work. |

---

## 11. Locally Served Models Cost Nothing (#190)

### Problem

`ModelPricing.price(for:)` ends in `return defaultPrice` — Sonnet-level $3/$15 per 1M —
for **any** name the table does not know. `SessionJSONLParser` accepts every
`type:"assistant"` line's `message.model`, including the model names a local server
reports when `ANTHROPIC_BASE_URL` points at ollama or LM Studio. So a user who
switched Claude Code to a local model watched the Cost Usage card keep climbing in
dollars, while the session/weekly quotas — which come from the Anthropic account and
were correctly flat — told them nothing was being spent.

`cachedSavings` had the same defect: cache savings priced at Anthropic rates for a
model nobody bills per token are a fabricated number, not an estimate.

The default exists for a narrow reason: it hedges **Anthropic** models released after
the table was written. Applied to `qwen3-coder` it is not a hedge, it is a wrong
number.

### Design: two free signals, one table, one order of precedence

`price(for:servedLocally:)` resolves in this order:

| # | Case | Price | Why |
|---|---|---|---|
| 1 | Known Anthropic model — exact, prefix, `opus`/`haiku` inference | table | Authoritative, and never overridden |
| 2 | Open-weight family name (`qwen`, `llama`, `gemma`, `mistral`, …) | **free** | In the shapes that occur — ollama, LM Studio, llama.cpp — nothing bills per token |
| 3 | Anything else, when the session was **served locally** | **free** | A loopback endpoint proves nobody can bill for the tokens |
| 4 | Anything else, no local provenance | `defaultPrice` | The hedge for a new Anthropic model, kept intact |

**Why both signals, and why this order.** Name alone needs a list that is always
behind: `phi4`, `granite` or a private fine-tune served over ollama still billed at
Sonnet rates. Provenance alone needs a config file to be present and correct, and
`ANTHROPIC_BASE_URL` is unset for most people — including everyone who reaches a
local runner some other way. Provenance settles what the name cannot: a local server
may serve a model we have never heard of, under any name. The name list settles what
the config cannot: it keeps a local model's cost at $0 even after the user has
switched back to the API, when the loopback signal is gone.

**Why rule 1 is not overridden by provenance.** `ANTHROPIC_BASE_URL` is a global,
current setting, but records are per-moment and the scan window is two days wide.
Zeroing `claude-sonnet-4-6` whenever a loopback URL happens to be configured would
retroactively erase real spend from before the switch. The loopback fact is evidence
about *unpriced* names only; for names the table knows, the table wins.

**Why provenance stops at midnight.** The same reasoning bounds *when* the signal
applies, not only to which names. Today is priced with it; yesterday's unpriced names
keep the Sonnet estimate. Applying it across the whole window would erase yesterday's
gateway estimate by precisely the mechanism rule 1 refuses — a current setting
reaching back over records written before it was true. The asymmetry is deliberate and
it is one-directional: the bound can *over*-report (a user who ran locally all of
yesterday sees Sonnet-rate dollars for a day nobody billed), never under-report. A
real z.ai bill quietly becoming $0 is the error this design will not make.

**A brand-new Anthropic model released tomorrow** lands in rule 4 and is estimated at
Sonnet rates, exactly as today. Anthropic model IDs contain `claude`, so none of the
local-family substrings can swallow one; and no Anthropic release is served from a
loopback endpoint, so provenance cannot quietly zero it. The failure mode of this fix
is the *opposite* of the old one: we never invent a price for an unrecognised
Anthropic model.

**Deliberately absent from the name list:** `glm-4`, `deepseek`, and friends. Those
names are also served by paid gateways (z.ai, DeepSeek, OpenRouter) through the same
`ANTHROPIC_BASE_URL` mechanism, so a name alone cannot say whether they cost anything.
They stay on the Sonnet estimate unless rule 3 proves the run was local — which is
the case that would otherwise have been guessed wrong in both directions.

### Provenance plumbing

`ClaudeLocalInferenceDetector` reads `~/.claude.json` — `env.ANTHROPIC_BASE_URL`, or the
`providers` array when that key is absent, the same file and shapes `ZaiUsageProbe`
already parses — and reports whether the active base URL resolves to a loopback host
(`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`). `ClaudeBarApp` passes
`isLocallyServed: { ClaudeLocalInferenceDetector.isLocallyServed() }` into
`ClaudeDailyUsageAnalyzer`; the analyzer's default is `{ false }` so tests never read
the developer's own config, matching `ClaudeUsageProbe`'s no-op resolver.

- **Resolved per scan, not at init**, so pointing the CLI at a local server takes
  effect on the next popover open without an app restart.
- **Applied to today only.** The signal describes the route as it is now, so yesterday's
  records stay on the estimate — see *Why provenance stops at midnight* above.
- **`env` outranks `providers`.** `providers` is the menu of gateways a user *may*
  switch between; `env.ANTHROPIC_BASE_URL` is the one Claude Code is routed at. A
  config listing `api.z.ai` alongside a leftover `localhost:11434` is the ordinary
  shape of a machine that tries both, and OR-ing the two would mark the window local
  and zero a real GLM/DeepSeek estimate for a machine running no local inference at
  all. `providers` is consulted only when `env` names no route.
- **Loopback only.** A remote `ANTHROPIC_BASE_URL` (z.ai, a corporate proxy) is
  still billed by somebody, so it proves nothing. An unparseable URL counts as
  remote: zeroing a cost because parsing failed would silently under-report spend.

### Known limitations

- A local server asked to serve `sonnet` (so the log says `claude-sonnet-4-6`) is
  still priced at list rates: the name is in the table, and a loopback URL says
  nothing about which Anthropic model would have been billed.
- **A hosted open-weight endpoint reads as $0, and nothing can re-price it.** A model
  whose name says open weights but which is metered by somebody else's cloud —
  `qwen3-max` on Alibaba, `mistral-large-2411` on La Plateforme, `gemma-3-27b-it`, or any
  `*/llama-*` id from OpenRouter, Together, Fireworks, DeepInfra or Groq — is reported
  free. The loopback signal is **not** an escape hatch here: rules 2 and 3 are OR'd on
  one line, so the name alone is enough to make the price free and no configuration can
  put it back. The name is the only signal available, and it is wrong for this case.
- **A local proxy in front of a paid upstream reads as $0.** LiteLLM on
  `localhost:4000` forwarding to z.ai, OpenRouter or a corporate model gateway satisfies
  rule 3 for every unpriced name, because loopback proves the *client* is on this
  machine, not that the *tokens* were. Same failure as the case above, and the more
  common shape in a team that fronts its providers through one router. The detector
  cannot tell a runner from a router: both answer on loopback.
- Cost remains a client-side estimate either way; §2's non-goals still stand.

### Tests

| Scenario | Assert |
|---|---|
| `qwen3-coder`, `qwen3-coder:30b` | cost and cache savings are 0, with cache tokens in the fixture |
| unpriced name, `servedLocally: true` | cost and cache savings 0 |
| unpriced name, no provenance | unchanged Sonnet estimate |
| unpriced name yesterday, `servedLocally: true` | yesterday keeps the Sonnet estimate |
| `claude-sonnet-4-6`, `servedLocally: true` | list price **and** cache savings kept |
| `glm-4.6`, `deepseek-r1` | still priced (paid-gateway names stay estimated) |
| analyzer over a local-model JSONL | `totalCost == 0` while `totalTokens == 1500` |
| analyzer over a private-fine-tune JSONL, loopback | cost and savings 0; same JSONL remote, both > 0 |
| detector | loopback hosts true, gateway/LAN/unparseable false, `providers[]` shapes |
| detector | a `localhost` entry in `providers[]` does not override a remote `env` route, and vice versa |

---

## References

- Issue [#207](https://github.com/tddworks/ClaudeBar/issues/207)
- [Anthropic Agent SDK — Track cost and usage](https://code.claude.com/docs/en/agent-sdk/cost-tracking)
- ccusage dedup rationale — [ryoppippi/ccusage#389](https://github.com/ryoppippi/ccusage/issues/389)
- claude-code [#6805](https://github.com/anthropics/claude-code/issues/6805) (3–8× stream-json over-count)
