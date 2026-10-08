# Codex API Probe - Architecture Design

## Overview

Add API-based usage probing for Codex, following the same dual-probe pattern as Claude (CLI/API mode switching). The Codex API probe reads OAuth credentials from `~/.codex/auth.json`, refreshes tokens via OpenAI's OAuth endpoint, and fetches usage data from the ChatGPT backend API.

## Current shape: Codex is data

Since `20be605` Codex has no Swift of its own. It is
[`Modules/Providers/Resources/Providers/codex.json`](../../../Modules/Providers/Resources/Providers/codex.json),
run by the one `Provider` and the `DataSources` workers
([TARGET_ARCHITECTURE.md](../../architecture/TARGET_ARCHITECTURE.md) §3):

| Data source | Credential | Fetch | Mapping | Fallback |
|---|---|---|---|---|
| `rpc` (default) | — | `jsonRpc`: `codex -s read-only -a never app-server` in the probe directory; `initialize` → `initialized` → `account/rateLimits/read` | `json`: `result.rateLimits.primary/secondary`, `rateLimitsByLimitId` (skipping `codex`), free-plan `whenEmpty` | `tty` |
| `api` | `jsonFile` `~/.codex/auth.json`, `refresh.oauth2` every 8 days or on 401/403 | `http` `GET chatgpt.com/backend-api/wham/usage` | `json`: headers first, `rate_limit.*_window`, `additional_rate_limits[]`, `plan_type`, credits against 1000 when `credits.has_credits` | — |
| `tty` (hidden) | — | `cli`: `codex -s read-only -a never`, types `/status`, answers the trust prompt with `1` | `text`: the three error phrases, `5h limit` / `Weekly limit` → `NN% left` within 12 lines | — |

Every finding below is now a line in that file, pinned by
`Modules/Providers/Tests/CodexDefinitionTests.swift`, which runs the old
probes' fixtures through it. Two behaviours changed on purpose: when RPC and
the terminal both fail, the **RPC** error is reported (the root cause, as for
Claude); and `resetText` for a reset already passed reads "Resets soon" in
both modes. The `CodexProvider`, `CodexUsageProbe`, `CodexAPIUsageProbe`,
`DefaultCodexRPCClient` and `CodexCredentialLoader` named in the plan below
no longer exist.

## Architecture Diagram (the original plan)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                     CODEX API PROBE - ARCHITECTURE                            │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────┐     ┌─────────────────────┐     ┌───────────────────────┐  │
│  │  External     │     │   Infrastructure     │     │     Domain            │  │
│  └──────────────┘     └─────────────────────┘     └───────────────────────┘  │
│                                                                               │
│  ┌──────────────┐     ┌─────────────────────┐     ┌───────────────────────┐  │
│  │ ~/.codex/    │────▶│ CodexCredential-    │────▶│ CodexOAuthCredentials │  │
│  │ auth.json    │     │ Loader (NEW)        │     │ (NEW)                 │  │
│  └──────────────┘     └─────────────────────┘     └───────────────────────┘  │
│                              │                                                │
│  ┌──────────────┐     ┌─────┴───────────────┐                                │
│  │ OpenAI OAuth │     │ CodexAPIUsageProbe  │                                │
│  │  Refresh URL │◀───▶│ (NEW)               │                                │
│  │  auth.openai │     │ implements          │                                │
│  │  .com/oauth  │     │ UsageProbe          │                                │
│  └──────────────┘     └─────────────────────┘                                │
│                              │                                                │
│  ┌──────────────┐     ┌─────┴───────────────┐     ┌───────────────────────┐  │
│  │ ChatGPT API  │     │ fetchUsage()        │────▶│ UsageSnapshot         │  │
│  │ /wham/usage  │◀────│ refreshToken()      │     │ (existing)            │  │
│  └──────────────┘     │ parseResponse()     │     │ - session quota       │  │
│                       └─────────────────────┘     │ - weekly quota        │  │
│                                                    │ - accountTier         │  │
│  ┌──────────────────────────────────────────┐     └───────────────────────┘  │
│  │                                           │                                │
│  │  CodexProvider (MODIFIED)                 │     ┌───────────────────────┐  │
│  │  ┌────────────────────────────────────┐   │     │ CodexProbeMode (NEW) │  │
│  │  │ + cliProbe: UsageProbe (existing)  │   │     │ .rpc (default)       │  │
│  │  │ + apiProbe: UsageProbe (NEW)       │   │     │ .api                 │  │
│  │  │ + activeProbe (mode-based)         │   │     └───────────────────────┘  │
│  │  └────────────────────────────────────┘   │                                │
│  │  Pattern: Same as ClaudeProvider          │     ┌───────────────────────┐  │
│  │  dual-probe (CLI/API) mode switching      │     │ CodexSettings-        │  │
│  └──────────────────────────────────────────┘     │ Repository (NEW)      │  │
│                                                    │ extends base          │  │
│  ┌──────────────────────────────────────────┐     │ + codexProbeMode()    │  │
│  │  ClaudeBarApp.swift (MODIFIED)            │     └───────────────────────┘  │
│  │  CodexProvider(                            │                                │
│  │    cliProbe: CodexUsageProbe(),            │                                │
│  │    apiProbe: CodexAPIUsageProbe(),         │                                │
│  │    settingsRepository: settingsRepository  │                                │
│  │  )                                         │                                │
│  └──────────────────────────────────────────┘                                │
│                                                                               │
│  ┌──────────────────────────────────────────┐                                │
│  │  SettingsView.swift (MODIFIED)            │                                │
│  │  + Codex probe mode picker (RPC / API)    │                                │
│  └──────────────────────────────────────────┘                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Component Table

| Component | Purpose | Inputs | Outputs | Dependencies |
|-----------|---------|--------|---------|--------------|
| `CodexOAuthCredentials` | Domain model for Codex auth tokens | N/A | Token data | None |
| `CodexCredentialLoader` | Load/save auth from `~/.codex/auth.json` | File path | `CodexCredentialResult` | FileManager |
| `CodexAPIUsageProbe` | Fetch usage via ChatGPT API | Access token | `UsageSnapshot` | `NetworkClient`, `CodexCredentialLoader` |
| `CodexProbeMode` | Enum for RPC vs API mode | N/A | Mode selection | None |
| `CodexSettingsRepository` | Store probe mode preference | Mode value | Persisted setting | `ProviderSettingsRepository` |
| `CodexProvider` (modified) | Support dual-probe (RPC + API) | Both probes | Active probe based on mode | `UsageProbe`, `CodexSettingsRepository` |

## Data Flow

1. **Auth loading**: `~/.codex/auth.json` → `CodexCredentialLoader` → `CodexOAuthCredentials`
2. **Token refresh**: If `last_refresh` > 8 days → POST to `https://auth.openai.com/oauth/token` → updated tokens saved back
3. **Usage fetch**: GET `https://chatgpt.com/backend-api/wham/usage` with Bearer token → parse response headers + body
4. **Snapshot mapping**: Session + Weekly quotas from headers/body, plan type from `data.plan_type`

## Auth File Format (`~/.codex/auth.json`)

```json
{
  "tokens": {
    "access_token": "...",
    "refresh_token": "...",
    "id_token": "...",
    "account_id": "..."
  },
  "last_refresh": "2025-01-15T10:00:00.000Z",
  "OPENAI_API_KEY": null
}
```

## API Response Format

### Response Headers
- `x-codex-primary-used-percent` - Session usage percentage
- `x-codex-secondary-used-percent` - Weekly usage percentage
- `x-codex-credits-balance` - Remaining credits

### Response Body
```json
{
  "rate_limit": {
    "primary_window": {
      "used_percent": 25.5,
      "reset_at": 1705312800,
      "reset_after_seconds": 3600
    },
    "secondary_window": {
      "used_percent": 45.0,
      "reset_at": 1705744800,
      "reset_after_seconds": 432000
    }
  },
  "code_review_rate_limit": {
    "primary_window": {
      "used_percent": 10.0
    }
  },
  "credits": {
    "has_credits": true,
    "unlimited": false,
    "balance": "950"
  },
  "plan_type": "plus"
}
```

## Token Refresh

- **Trigger**: `last_refresh` is null OR older than 8 days
- **Endpoint**: `POST https://auth.openai.com/oauth/token`
- **Content-Type**: `application/x-www-form-urlencoded`
- **Parameters**: `grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=...`
- **Error Handling**:
  - `refresh_token_expired` → Session expired, re-login required
  - `refresh_token_reused` → Token conflict, re-login required
  - `refresh_token_invalidated` → Token revoked, re-login required

## Key Design Decisions

1. **Follow ClaudeProvider dual-probe pattern**: RPC (default) and API modes with user-switchable preference
2. **Separate CodexCredentialLoader**: Different file format and refresh strategy than Claude credentials
3. **ISP-compliant**: New `CodexSettingsRepository` sub-protocol extending base `ProviderSettingsRepository`
4. **Form-urlencoded token refresh**: Matches the OpenAI OAuth spec (not JSON body)
5. **Header-first usage parsing**: Check response headers first, fall back to response body

## Files to Create/Modify

### New Files
- `Sources/Domain/Provider/Codex/CodexProbeMode.swift`
- `Sources/Infrastructure/Adapters/CodexCredentialLoader.swift`
- `Sources/Infrastructure/CLI/Codex/CodexAPIUsageProbe.swift`
- `Tests/InfrastructureTests/CLI/Codex/CodexAPIUsageProbeTests.swift`
- `Tests/InfrastructureTests/Adapters/CodexCredentialLoaderTests.swift`

### Modified Files
- `Sources/Domain/Provider/ProviderSettingsRepository.swift` - Add `CodexSettingsRepository` protocol
- `Sources/Domain/Provider/CodexProvider.swift` - Add dual-probe support (cliProbe + apiProbe)
- `Sources/Infrastructure/Storage/JSONSettingsRepository.swift` - Implement `CodexSettingsRepository`
- `Sources/App/ClaudeBarApp.swift` - Pass API probe to CodexProvider
- `Sources/App/Views/SettingsView.swift` - Add Codex probe mode picker
## Findings since

This plan covered the API probe. What was learned afterwards, mostly about the RPC probe (the default):

- **RPC sequence**: `codex -s read-only -a never app-server`, then JSON-RPC over stdio: `initialize` (`clientInfo: {name: "claudebar"}`), the `initialized` notification, then `account/rateLimits/read`. Read `result.rateLimits.{primary,secondary,planType}`. Skip notifications (messages with no `id`) while waiting for the response.
- **Window fields**: `usedPercent`, `resetsAt` (Unix **seconds**) and `windowDurationMins`. Until PR #305 the probe formatted `resetsAt` into "Resets in 4h 42m" and threw the `Date` away. `UsageQuota.resetsAt` was always nil for Codex, so the menu bar fell back to parsing text, in a different format ("4h 42m" rather than "2:33") and frozen at probe time. Pace-aware status, burn rate and `percentTimeElapsed` didn't work for Codex either (#298, root cause of #218). Keep both `resetsAt` and `windowDuration` on `CodexRateLimitWindow`.
- **The primary window isn't always 5 hours.** A live `account/rateLimits/read` in 2026-09 returned `{"usedPercent":94,"windowDurationMins":10080,"resetsAt":1790500839}` as the **primary** window, which is a weekly window. Without `windowDuration` the pace math assumes a 5-hour session. `mapRateLimitsToSnapshot` still maps primary → `.session` and secondary → `.weekly` by position, so the label can be wrong even though the pace math is right.
- **No windows**: `planType == "free"` gets one "Free plan" quota at 0% used. Any other plan throws "No rate limits available yet - make some API calls first".
- **Approval flag (#259)**: Codex removed `untrusted` from `--ask-for-approval` (only `on-request` and `never` are left). An unknown value makes the CLI exit while parsing arguments, which broke the app-server *and* the TTY fallback, surfacing as "Could not find usage limits in Codex output". `never` is accepted by old and new builds and can't stall a non-interactive pipe on an approval prompt. `-s read-only` stays. Both paths share `baseArguments`.
- **TTY fallback**: when RPC throws, run `codex -s read-only -a never` with `/status\n` as input, strip ANSI codes, and within 12 lines after the "5h limit" and "Weekly limit" labels find `NN% left`. That gives no reset timestamps, so there's no countdown on this path. `data not available yet`, `update available` + `codex`, and `not logged in` / `please log in` are mapped to errors.
- **Directory-trust prompt (#267)**: Codex 0.150+ asks "Do you trust the contents of this directory?" before it does anything interactive, and it trust-checks the directory on **both** probe paths: the `app-server` RPC handshake and the TTY fallback. A probe that inherits the app's cwd (`/` from Finder/launchd) stalls until timeout, surfacing as "Could not find usage limits in Codex output". Unlike Claude, Codex 0.150 keeps trust state in SQLite with no file ClaudeBar can write, so both paths run in `Application Support/ClaudeBar/Probe` (`ProbeWorkingDirectory.resolve()`, shared with the Claude probes) and the TTY fallback auto-answers the prompt with `"1"` (the trust option's number). The answer persists once given.
- **A stalled app-server (#517)**: `codex app-server` can stop answering without exiting. With no deadline the read waited forever, the account showed *Syncing…* until the app was relaunched, and every later refresh joined the stuck one. The exchange (handshake, call and follow-ups) now has `timeout` seconds, 15 by default: at the deadline the transport is closed, which stops the app-server and ends the read, and the fetch fails with *Request timed out*, so the TTY fallback runs.
- **Process leak (#113)**: each refresh starts its own `app-server`. The transport the probe creates **must** be closed in a `defer`. Before this was fixed, thousands of orphaned `codex app-server` processes built up.
- **API mode credits**: `x-codex-credits-balance` (header) or `credits.balance` (body) is shown against a hard-coded limit of 1000, only when `credits.has_credits` is `true`. The API doesn't return a limit, and an account without credits reports `"balance": "0"` (a string), which read as $1000 spent ([#444](https://github.com/tddworks/ClaudeBar/issues/444)). Headers `x-codex-primary-used-percent` / `x-codex-secondary-used-percent` take precedence. Reset times always come from `rate_limit.*_window`.
- **No fallback between the modes the person picks.** Only `rpc` falls back, to the hidden `tty`. A failing `api` doesn't try `rpc`.
- **Extra buckets (#178)**: GPT-5.3-Codex-Spark (Pro research preview) has its own 5h + weekly windows, separate from the main limits. Both modes carry the data. RPC: `account/rateLimits/read` returns `result.rateLimitsByLimitId`, a map of `RateLimitSnapshot` keyed by limit id (`codex` is the main bucket and mirrors the top-level `rateLimits`; other keys are the extras). API: the body has `additional_rate_limits`, an array of `{limit_name, metered_feature, rate_limit}` where `rate_limit` is a `RateLimitStatusDetails` object that may be null and holds nested `primary_window` / `secondary_window` objects with the same `used_percent` / `reset_at` / `reset_after_seconds` fields as the main windows (plus `limit_window_seconds`, kept as the quota's `windowDuration`). Both paths append the extra quotas **after** the main session/weekly rows — the menu bar renders `quotas.first`, so the main limits must lead. Labels are trimmed for the menu (`Codex Spark` / `codex_spark` → "Spark"); the extra weekly window becomes "Spark 7d". Entries with no parseable window are skipped, and an absent map/field leaves the snapshot unchanged.
- **Passive until verified (#216)**: spawning `codex app-server` (or the TTY fallback) while the CLI is unauthenticated can make the CLI open the ChatGPT browser login all by itself — ClaudeBar never runs `codex login`, the login flow is the CLI's own behavior. Two gates: (1) only `.interactive` refreshes — genuine clicks: the Refresh button, Touch Bar / notch refresh, `claudebar://refresh`, provider switch, probe-mode test — may run the RPC probe, and a success persists `codex.verifiedAtLeastOnce` via `CodexSettingsRepository`; `.background` (the menu-bar poll) and `.passive` (the popover-open refresh, a third `RefreshKind` case added for this) return the last snapshot without spawning, or surface "Codex CLI session not checked. Click Refresh or Connect to check Codex status." through `lastError`. The popover renders Claude's daily-usage cards, so `.passive` is deliberately not `.background`: Claude attaches the daily report for both `.interactive` and `.passive` and only skips the JSONL scan on the background poll (#204); the default implementation ignores the kind, so the other 18 providers are unaffected. (2) Defense in depth, `CodexUsageProbe.probe()` refuses to spawn the CLI at all when `~/.codex/auth.json` does not exist (throws `authenticationRequired`) — the file's *existence* is checked, not its contents, so API-key users keep working, and the API probe keeps its own OAuth gate on `loadCredentials()`. The loader resolves the auth path exactly like the CLI: `$CODEX_HOME/auth.json` when `CODEX_HOME` is set, `~/.codex/auth.json` otherwise. `isAvailable()` deliberately still only checks the binary — it answers "provider exists", not "allowed to actively probe"; the verified flag is the third state.


## Independent Codex accounts

Additional accounts reuse `ProviderAccountConfig` and `MultiAccountSettingsRepository`.
`codex.json`'s `accounts` says how one is added (`folder`: saved as `codexHome`,
its login's `account` claim saved as `chatgptAccountId`; `signIn`: `codex -c cli_auth_credentials_store="file" login` with `CODEX_HOME` set), and what an added login changes: `accounts.patch`, an RFC 7396 merge patch
per data source kind (`"tty": null` leaves the terminal out). One Codex `Provider`
(the product) owns its `Account`s (the logins, [CANONICAL_MODEL](../../architecture/CANONICAL_MODEL.md#1--the-tree));
`provider.addAccount(signedInAt:)` checks a folder and adds it (`provider.signIn()` runs `codex login` into a new one first), compound ID
`codex.<local UUID>`, the default keeping `codex`. Each login is its own pill,
enable toggle and menu-bar choice — users pin two accounts at once instead of
selecting one active account within Codex.

Settings contain the email, canonical Codex directory and expected ChatGPT account
ID, never tokens. Setup rejects duplicate directories (including symlinks), the
default directory and duplicate ChatGPT account IDs. Email is a display identifier,
not an authentication key; separate workspaces can share an email.

The `identity` rule checks the expected account ID before and after a fetch.
Both data sources read the account's own `{{account.codexHome}}/auth.json`; a
refreshed API token is written back only there. RPC sets `CODEX_HOME` on the child
process, unsets the other OpenAI auth variables, and forces file credential storage
(`-c cli_auth_credentials_store="file"`) for added accounts, which have no TTY
fallback — the terminal would read the global login. Missing or replaced credentials
fail closed. A provider coalesces simultaneous refreshes so overlapping UI and
background polls cannot rotate its refresh token twice.

RPC identity comes from `account/read` with `refreshToken: false`, which also
supports the default Keychain login. File credentials provide the email from the
ID token as display metadata only; decoding that claim does not verify a token.
Full email remains in menu-bar tooltips when a visible label is shortened.

## Desktop app CLI

The Codex desktop app ships its own `codex` inside its bundle, so a person with
only the app has no `codex` on the PATH. `codex.json` lists those places after
the name in `cli`
([where a provider's CLI is](../../architecture/ENGINE_DESIGN.md#27--where-a-providers-cli-is)).
A ChatGPT-bundled copy under `ChatGPT.app/Contents/Resources/codex-cli/` was
reported in [#458](https://github.com/tddworks/ClaudeBar/pull/458), not yet
confirmed in a shipping build; add it once it is.
