# Claude probe design

Contributor notes for the Claude provider. For setup, see the [README](README.md).

## Sources

| Probe | Source | Notes |
|---|---|---|
| CLI (default) | `claude /usage --allowed-tools ""` in a PTY, run from `~/Library/Application Support/ClaudeBar/Probe` | The screen is rendered with SwiftTerm and then scraped |
| CLI, pay-as-you-go | `claude /cost` | Used only when `/usage` says it's "only available for subscription plans", or shows the API-billing panel for an account that isn't a subscription |
| API | `GET https://api.anthropic.com/api/oauth/usage`, header `anthropic-beta: oauth-2025-04-20` | Uses the Claude Code OAuth token |
| Token refresh | `POST https://platform.claude.com/v1/oauth/token` with Claude Code's public `client_id` | Scopes: `user:profile user:inference user:sessions:claude_code` only. Asking for more scopes (e.g. `user:mcp_servers`) makes the refresh fail |
| Account identity | `~/.claude.json` → `oauthAccount` (email, display name, `billingType`) | CLI v2.1.79+ moved account details to a separate Status tab |
| Guest passes | `claude /passes`, which copies the link to the clipboard | Max only (#243) |
| Daily usage | `~/.claude/projects/*/*.jsonl` | Deduplicated by `(message.id, requestId)`, because Claude Code writes the same usage more than once |
| Local File mode | `~/Library/Application Support/Claude/buddy-tokens.json` → `{"tokens-today": {"date": "YYYY-MM-DD", "tokens": N}}` | Claude Desktop's daily token counter (#198). Injected as `ClaudeDesktopFileUsageProbe`; tests pass a temp `claudeDir`/`calendar`/`now`, never the real home path |

## Fallback chain

`ClaudeProvider` runs the chosen mode first and, if it fails, the other one:

- **CLI → API**: when the API probe has credentials. This recovers from `/usage` parse failures and from subscriptions the CLI can't see.
- **API → CLI**: only while `claude.cliFallbackEnabled` is on (the default). Users asked for an off switch because running the CLI in the background can cause prompts (e.g. SSH keys).
- **Never after `ProbeError.rateLimited`.** The CLI uses the same backend, so falling back only makes the throttling worse.
- **Local File → nothing.** buddy-tokens.json is a daily token total while CLI/API report five-hour/weekly windows; swapping probes would present the wrong semantic as the user's chosen data. A failing file probe surfaces its error, and `isAvailable` answers for the file alone — CLI/API availability is irrelevant in this mode (#198).
- **Both fail**: report the *primary* error. The fallback's error is incidental and would send users after the wrong problem.

## Local File mode (buddy-tokens.json)

- `ClaudeProbeMode.localFile` persists as the raw value `"localFile"` through the existing String storage; unknown stored values still fall back to `.cli`.
- The probe maps the daily total to an `ExtensionMetric` card ("Tokens Today"), not a `UsageQuota` — there is no cap, so a percentage would be a lie. `quotas` stays empty, which keeps the menu bar (percentage-based) honest; the popover renders the metric card.
- Defensive parsing per the maintainer's requirements on #198: missing/unreadable file → `.noData`; invalid JSON, missing `tokens-today`/`tokens`/`date`, negative tokens, or an unparseable date → `.parseFailed` with a structural reason (never file contents); a `date` that isn't the user's **local** calendar day (via the injected `Calendar`) → `.noData`, so stale data never renders as today's usage. File contents are never logged — the file log has no redaction.
- `backgroundRefreshFloor` is `nil` in Local File mode: reading a small local file is cheap.

## CLI screen parsing

- **Render the whole buffer, not just the visible screen.** In recent CLI versions `/usage` grew taller than the probe's 160×50 terminal (a usage-contribution report was added), which pushed the quota sections into scrollback. The renderer now reads visible rows plus scrollback.
- **Wait for the screen to settle.** `/usage` draws its cost panel and a "Loading usage data…" placeholder within milliseconds, then fills in the quota bars from a second request. Going idle doesn't mean it's done. The PTY buffer only ever grows, so "still loading" can't be detected by the placeholder disappearing. `CLICompletionRule.claudeUsage` waits for a marker that only a finished screen has (quota data or an error). A capture that still ends on the placeholder is reported as a probable rate limit, not a parse failure (#271, #253).
- **Deduplicate "Resets …".** When the CLI redraws with cursor positioning, wide progress-bar characters can shift columns, so a line reads `Resets 4:59pm (TZ)Resets 4:59pm (TZ)`. The parser keeps the last occurrence.
- **Reset text formats**: relative (`2h 15m`), time only (`4:59pm`), `Dec 28`, `Jan 15, 3:30pm`, `Dec 25 at 4:59am`, with or without an explicit year and a trailing `(Area/City)` timezone. Newer CLIs put the percentage on the same line (`Resets 3pm (Europe/Amsterdam)  27% used`). Dates without a year roll forward to the next future occurrence.
- **Section labels**: "Current session", "Current week (all models)", "Current week (Opus)", "Current week (Sonnet only)" / "(Sonnet)", and "Current week (Fable". The Fable label is matched only up to the opening parenthesis so that a future "(Fable 5)" still matches. Fable resets at its own time and falls back to the all-models weekly reset.
- **Trust prompt**: the CLI auto-answers "Esc to cancel", "Ready to code here?", "Press Enter to continue", "ctrl+t to disable" and "Yes, I trust this folder". If the prompt is still on screen afterwards, ClaudeBar writes `projects["<probe dir>"].hasTrustDialogAccepted = true` into `.claude.json` (respecting `CLAUDE_CONFIG_DIR`) and retries. It leaves the file alone if the file is missing, isn't valid JSON, or contains types it doesn't expect.
- **Rate-limit text**: "rate limited", "rate limit exceeded" and "too many requests" count as errors, but lines containing "rate limits are" don't. That excludes promotions such as "rate limits are 2x higher".

## Classifying the account

- The header text "API Usage Billing" doesn't identify an account type. Subscriptions with Extra Usage credits show it next to real quota bars. Treating that header as pay-as-you-go made the session and weekly bars disappear.
- Pay-as-you-go is detected from the explicit "/usage is only available for subscription plans" message, or from a finished cost panel with **no** percentages anywhere.
- Even then, if `billingType` in `~/.claude.json` shows a subscription (e.g. `apple_subscription`, `stripe_subscription`), the CLI probe fails instead of running `/cost`. `/cost` would *succeed* with $0.00 and stop the API fallback that can read the real quota (#271, a Max plan billed through Apple).

## API fields

- `five_hour`, `seven_day`: `utilization` (percent used) and `resets_at` (ISO 8601).
- `seven_day_opus` and `seven_day_sonnet` are legacy and now `null`. Model-scoped limits arrive in the generic `limits[]` array as `kind: "weekly_scoped"`, with `percent` and `scope.model.display_name` (e.g. "Fable 5"). The quota key is the first word of the display name, lowercased (`fable`). It **must** match the key the CLI probe hard-codes, or a saved `model:<name>` menu-bar selection stops working when the user switches modes. Entries in `limits[]` that duplicate `five_hour`/`seven_day` are skipped for now. If those legacy fields ever go `null`, extend the loop to the `session`/`weekly_all` kinds.
- Remaining quota isn't clamped, so a model over its quota shows a negative value.
- Extra Usage: prefer `spend` (`used`, `limit`, `enabled`) and fall back to legacy `extra_usage`. A missing or `null` limit means no cap. A limit that's present but invalid drops the whole entry, so it isn't mistaken for "uncapped".
- Tier: `claude_max`/`max`, `claude_pro`/`pro`, `api`/`claude_api`.

## Credentials

- Lookup order: `~/.claude/.credentials.json` → Keychain `Claude Code-credentials` → `CLAUDE_CODE_OAUTH_TOKEN`. A setup-token has only the `user:inference` scope, so it comes last. It has no refresh token, so a 401/403 with it isn't retried.
- The Keychain is read through `/usr/bin/security find-generic-password -w`, not `SecItemCopyMatching`. The item was created by Claude Code, which has a different code signature, so `SecItemCopyMatching` prompts on every access and "Always Allow" doesn't survive a ClaudeBar rebuild. The Apple-signed `security` tool doesn't prompt (#94).
- **macOS 26 hex quirk**: `security -w` returns any password containing a byte outside printable ASCII as lowercase hex. Pretty-printed JSON has newlines, which is enough to trigger it. ClaudeBar writes compact JSON, and decodes all-hex payloads when reading (valid JSON starts with `{`, which isn't a hex digit) (#255).
- Refresh write-back merges into the existing `claudeAiOauth` object so fields ClaudeBar doesn't model (e.g. `scopes`) are kept. Claude Code reads the same record (#256).
- The credential cache expires after 5 minutes so a re-login in the CLI is picked up. It's cleared on any auth failure. A refresh token is single-use, and the CLI may already have used it (#143).
- A failed Keychain read is logged with the `security` exit status. Before this, it looked like "no credentials" to someone who was signed in (#271).

## Rate limiting (API)

- A 429 stores `retryAt` from `Retry-After` (seconds or an HTTP date). If the header is missing, malformed, in the past or `0`, the wait is 5 minutes. The endpoint has been seen sending `Retry-After: 0` while still returning 429 (anthropics/claude-code#30930). Until `retryAt`, `probe()` returns straight away without touching the network.
- Successful snapshots are cached for 15 minutes. After a quiet period, even a single call has triggered a one-hour `Retry-After`, which suggests the throttle works as a penalty box. A 5-minute cache still hit it. `backgroundRefreshFloor` is 15 minutes in API mode so polling doesn't just reread the cache (#204).

## Known limits

- The credential file path ignores `CLAUDE_CONFIG_DIR`. Only the trust write and `.claude.json` lookup respect it.
- The OAuth `client_id` is Claude Code's. If Claude Code changes it, token refresh breaks.
