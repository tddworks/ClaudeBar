# Codex API Probe - Architecture Design

## Overview

Add API-based usage probing for Codex, following the same dual-probe pattern as Claude (CLI/API mode switching). The Codex API probe reads OAuth credentials from `~/.codex/auth.json`, refreshes tokens via OpenAI's OAuth endpoint, and fetches usage data from the ChatGPT backend API.

## Architecture Diagram

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
    "balance": 950.0
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
- `Sources/Infrastructure/Storage/UserDefaultsProviderSettingsRepository.swift` - Implement `CodexSettingsRepository`
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
- **Process leak (#113)**: each refresh starts its own `app-server`. The transport the probe creates **must** be closed in a `defer`. Before this was fixed, thousands of orphaned `codex app-server` processes built up.
- **API mode credits**: `x-codex-credits-balance` (header) or `credits.balance` (body) is shown against a hard-coded limit of 1000. The API doesn't return a limit. Headers `x-codex-primary-used-percent` / `x-codex-secondary-used-percent` take precedence. Reset times always come from `rate_limit.*_window`.
- **No fallback between modes.** `CodexProvider` runs only the selected probe. Unlike Claude, a failing mode doesn't try the other.
- **Extra buckets (#178)**: GPT-5.3-Codex-Spark (Pro research preview) has its own 5h + weekly windows, separate from the main limits. Both modes carry the data. RPC: `account/rateLimits/read` returns `result.rateLimitsByLimitId`, a map of `RateLimitSnapshot` keyed by limit id (`codex` is the main bucket and mirrors the top-level `rateLimits`; other keys are the extras). API: the body has `additional_rate_limits`, an array of `{limit_name, metered_feature, rate_limit}` where `rate_limit` is a `RateLimitStatusDetails` object that may be null and holds nested `primary_window` / `secondary_window` objects with the same `used_percent` / `reset_at` / `reset_after_seconds` fields as the main windows (plus `limit_window_seconds`, kept as the quota's `windowDuration`). Both paths append the extra quotas **after** the main session/weekly rows — the menu bar renders `quotas.first`, so the main limits must lead. Labels are trimmed for the menu (`Codex Spark` / `codex_spark` → "Spark"); the extra weekly window becomes "Spark 7d". Entries with no parseable window are skipped, and an absent map/field leaves the snapshot unchanged.
