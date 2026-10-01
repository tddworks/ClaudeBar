# Oh My Pi: probe design

Contributor research for the Oh My Pi provider (`omp`). User-facing setup is in [README.md](README.md).

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
