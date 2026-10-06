# Oh My Pi: design

Contributor research for the Oh My Pi provider (`omp`). User-facing setup is in [README.md](README.md).

## As data

Oh My Pi is `Modules/Providers/Resources/Providers/omp.json` and `omp-usage.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md); no Swift names it. Ported from #387. The sections below are the research; the payload and the labels are unchanged. Its `usageHistory` reads omp's session logs ([Usage history](#usage-history)).

- **A `command` fetch** runs `omp usage --json` over pipes; a non-zero exit is `cli.nonzero`, which never carries the output (it holds account emails and ids). The script slices the first `{` to the last `}` and reads numbers as exact texts (`jsonDecimal`).
- **Each limit is a quota with its `group`** — the provider, and the account tag when one provider has several. A capped USD limit is money left of its cap (`left: {money, of}`), its share following the cents shown.
- **`notes`** carry what has nothing to measure: an account with no usage, and spend with no cap. Each is a row under its group, named by its own `label`.
- **Not taken:** card and menu-bar titles (`compactTitle`, `menuBarTitle`), which are the page's. The 5-minute floor is `cache.ttl: 300`, so a click within 5 minutes shows the cached report too.

## Source

One CLI call: `omp usage --json` (30 s timeout). There is no API fallback. Exit code ≠ 0 becomes `executionFailed("omp usage exited with code N")`; the raw output is **never** put in the error, because it carries account emails and ids and the error text reaches the UI.

The output is sliced from the first `{` to the last `}` before decoding, because status lines or appended stderr can surround the JSON.

### Running from the menu bar

`omp` is a Bun/Node-shebang script. From the launchd (menu bar) context `/usr/bin/env bun` failed, because the login-shell PATH isn't there. Probes now run with a PATH that adds the common install directories and the resolved binary's own directory, and binary lookup also searches `~/.bun/bin` (introduced with this provider, 0.4.71).

### Background refresh floor

The provider declares a 5-minute `backgroundRefreshFloor`: `omp usage` caches upstream reports itself, so faster polls only respawn Bun for identical data. Interactive refreshes ignore the floor. The monitor uses the slowest floor in the active set, so omp slows every provider refreshed in the same background cycle.

## Payload (seen with omp v16.4.6)

```json
{
  "generatedAt": 1783869272381,
  "reports": [{
    "provider": "anthropic",
    "limits": [{
      "label": "Claude 5 Hour",
      "scope":  { "provider": "anthropic", "windowId": "5h", "tier": null, "accountId": null },
      "window": { "id": "5h", "durationMs": 18000000, "resetsAt": 1783885200000 },
      "amount": { "usedFraction": 0.08, "remainingFraction": 0.92, "unit": "percent" }
    }],
    "metadata": { "email": "user@example.com", "accountId": null, "projectId": null }
  }],
  "accountsWithoutUsage": [{ "provider": "openai-codex", "type": "oauth", "email": "..." }]
}
```

- Percent remaining prefers `remainingFraction`, then `1 - usedFraction`, then `(limit - used) / limit`.
- `window.resetsAt` and `durationMs` are epoch **milliseconds**. `durationMs` feeds pace/burn-rate math directly, so a `timeLimit` quota doesn't fall back to the default 7-day assumption.
- Identity is spread out: `metadata.email` → `metadata.accountId` → `metadata.projectId`, then a limit's `scope.accountId` / `scope.projectId` (Gemini and Kimi carry identity in limit scopes). This mirrors omp's own `reportAccountLabel`.
- Upstream ids mapped to short names: `anthropic` Claude, `openai-codex` Codex, `zai` Z.ai, `google-gemini-cli` Gemini, `google-antigravity` Antigravity, `github-copilot` Copilot, `kimi-code` Kimi, `minimax-code` MiniMax, `minimax-code-cn` MiniMax CN, `opencode-go` OpenCode Go. That's every id omp v16.4.6's usage registry (`@oh-my-pi/pi-ai/src/usage/*`) emits; unknown ids are title-cased.

## Labels are keys

Each limit becomes a `timeLimit` quota labelled `"<Provider> [Tier] [Meter] <window> [· account]"`, e.g. "Claude 5h", "Codex Spark 7d", "Z.ai Tokens 5h". **The label is the persisted quota key** (menu-bar selections, Notify! gauge), so it must be unique and stable:

- **Account discriminator** only when several reports share one upstream provider: the email local part (≤16 chars) or the first 8 chars of an opaque id, else `#<index>`.
- **Meter** only when two limits share a (tier, window) on one account, e.g. Z.ai's token and request quotas are both `5h`. The meter is `amount.unit` capitalised, unless it's `percent`.
- **Final guard**: any remaining collision gets ` (2)`, ` (3)`…
- The raw window token (`scope.windowId` → `window.id` → `window.label`) is never humanised in the label.

Presentation is separate and may change freely:

- **`group`**: one collapsible popover section per upstream account ("Codex · work").
- **`compactTitle`** (card title inside a section): prefers a compact id ("5h", "1mo"), then a token derived from `durationMs`, then the limit's own `label`, then the window label. Label-derived titles drop a leading provider name (Gemini embeds it) and skip the meter prefix (Copilot's "Premium Requests" already names it). Kimi was the trigger: `windowId` `300time_unit_minute` with label "5h limit", and a summary row `default` labelled "Total quota".
- **`menuBarTitle`**: the label with discriminators longer than 8 chars cut to 7 + "…", then re-uniquified, because distinct long tags can share a prefix.

## Monetary rows

`amount.unit == "usd"`:

- With a positive `limit`: a spend meter, "$used of $cap", still driven by percent. `used`/`limit` decode as `Decimal` straight from the JSON token, so 1.005 rounds to $1.01, not $1.00.
- With no `limit`: an account note "`<token>` usage $X spent · no cap". No percentage is invented.

## Accounts without usage

- A report with zero usable limits (Ollama has no quota API) still gets a "No usage reported" row.
- An `accountsWithoutUsage` entry gets one unless it matches an account that did report. Matching is per upstream provider: normalised email when both sides have one, else exact account id. **Org-scoped entries are never merged**, since an org is a distinct limit pool. Duplicate org-less entries collapse into one row (0.4.72).
- Nothing at all to show → `ProbeError.noData`.

`accountEmail` on the snapshot is set only when exactly one distinct email appears across the payload.

## Usage history

*TODAY'S USAGE*, the 30-day chart and the leaderboard read omp's own session logs, not `omp usage`. Researched against omp 18.6.1 (installed) and its source at 18.6.2: `@oh-my-pi/pi-utils` `dirs.ts`, `pi-coding-agent` `session/session-entries.ts` and `session-manager.ts`, and `@oh-my-pi/omp-stats`, omp's own usage dashboard, whose `parser.ts` and `db.ts` decide what counts.

The mapping is `usageHistory` in [`omp.json`](../../../Modules/Providers/Resources/Providers/omp.json): one log, every `*.jsonl` under the sessions folder, in two `shapes`, and a 30-minute `sessionGap` like Claude's and Codex's. Why each part is what it is:

- **Where.** `getSessionsDir()` is `<agent dir>/sessions`, the agent dir `PI_CODING_AGENT_DIR` or `~/.omp/agent`. A main session is `<project>/<session>.jsonl`; its subagents' and advisor's transcripts sit one folder deeper (`<project>/<session>/<agent>.jsonl`, `__advisor.jsonl`), nested subagents deeper still. omp-stats reads every `*.jsonl` under each project folder, and so does the glob.
- **One record, two shapes.** A turn is `{"type":"message","message":{"role":"assistant","usage":{…}}}`. A model call outside the conversation (memory, judgment, an advisor's) is `{"type":"model_usage","usage":{…}}`, written by `appendModelUsage`. omp-stats counts both and nothing else, so `records` has both `shapes`, each read whole ([daily-usage design §2](../../features/daily-usage/design.md)). Only `message` entries have a `message`, so `$.message.role` picks out assistant turns alone, and no line has both shapes.
- **Not counted, on purpose.** A `task` tool result carries `details.usage`, the sum of its subagent's turns, which are already counted from the subagent's own transcript; omp-stats skips it too, as it skips `generate_image`'s `details.usage`. User and tool-result messages carry no `usage`.
- **Forks copy whole entries.** A forked session copies the parent's entries with their `id` and `timestamp`: 19% of the usage lines on the machine this was measured on. omp-stats dedupes on `(entry_id, timestamp)` (`backfillForkDuplicates`), and so does `id`. An entry id is 8 hex characters, so the id alone repeats across sessions (31 of 511,851 ids there, at different times); the time keeps those apart.
- **Tokens.** pi-ai's `Usage.input` is the non-cached input for every provider (OpenAI's cached tokens are taken out in `calculateOpenAIUsageAccounting`), so there is no `inputIncludesCacheRead`. On the measured machine `totalTokens == input + output + cacheRead + cacheWrite` held for all 510,295 records across 8 providers. `usage.orchestration` (provider-side tokens outside those four) isn't read; no record there carried it.
- **Time.** `$.timestamp` is ISO 8601, written with the entry. The message's own `timestamp` is epoch milliseconds, which `at` would read as seconds.
- **Cost.** `usage.cost.total`, the USD omp recorded for the call (its model catalog's price, or what the provider reported), so the history knows its cost without a price list and declares no `model`. A call omp recorded at $0 adds $0: most Kimi Code calls on the measured machine. omp-stats re-prices some zero-cost calls from its catalog, so its totals can be higher.
- **Not read.** Named profiles (`~/.omp/profiles/<name>/agent/sessions`), the XDG layout (`$XDG_DATA_HOME/omp/sessions` once migrated), and a `PI_CODING_AGENT_SESSION_DIR` / `--session-dir` override. A `PI_CODING_AGENT_DIR` exported only in a shell profile is invisible when ClaudeBar starts from Finder or at login.
