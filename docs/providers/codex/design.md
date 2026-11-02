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
| `rpc` (default) | — | `jsonRpc`: `codex -s read-only -a never app-server` in the probe directory; `initialize` → `initialized` → `account/rateLimits/read`; an error answer saying `authentication required` is *Authentication required* | `json`: `result.rateLimits.primary/secondary` named by their length (`kindByWindow`), `rateLimitsByLimitId` (skipping `codex`), `planType`, `rateLimitResetCredits.availableCount` as a note, `rateLimits.credits` as a *Credits* note, free-plan `whenEmpty` | `tty`, `sameLogin` |
| `api` | `jsonFile` `~/.codex/auth.json`, `refresh.oauth2` every 8 days or on 401/403 | `http` `GET chatgpt.com/backend-api/wham/usage` | `json`: headers first, `rate_limit.*_window` named by their length (`kindByWindow`), `additional_rate_limits[]`, `plan_type`, `rate_limit_reset_credits.available_count` as a note, `credits` as a *Credits* note | — |
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
- `x-codex-credits-balance` - The credit balance (a live `wham/usage` on 2026-11-02 sent no `x-codex-*` header; Codex reads them from its model requests)

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
    "balance": "62500.0000000000"
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
- `Sources/Domain/Settings/CodexProbeMode.swift`
- `Sources/Infrastructure/Adapters/CodexCredentialLoader.swift`
- `Sources/Infrastructure/CLI/Codex/CodexAPIUsageProbe.swift`
- `Tests/InfrastructureTests/CLI/Codex/CodexAPIUsageProbeTests.swift`
- `Tests/InfrastructureTests/Adapters/CodexCredentialLoaderTests.swift`

### Modified Files
- `Sources/Domain/Provider/ProviderSettingsRepository.swift` - Add `CodexSettingsRepository` protocol
- `Sources/Domain/Provider/CodexProvider.swift` - Add dual-probe support (cliProbe + apiProbe)
- `Sources/Infrastructure/Settings/Storage/JSONSettingsRepository.swift` - Implement `CodexSettingsRepository`
- `Sources/App/ClaudeBarApp.swift` - Pass API probe to CodexProvider
- `Sources/App/Views/SettingsView.swift` - Add Codex probe mode picker
## Findings since

This plan covered the API probe. What was learned afterwards, mostly about the RPC probe (the default):

- **RPC sequence**: `codex -s read-only -a never app-server`, then JSON-RPC over stdio: `initialize` (`clientInfo: {name: "claudebar"}`), the `initialized` notification, then `account/rateLimits/read`. Read `result.rateLimits.{primary,secondary,planType}`. Skip notifications (messages with no `id`) while waiting for the response.
- **Window fields**: `usedPercent`, `resetsAt` (Unix **seconds**) and `windowDurationMins`. Until PR #305 the probe formatted `resetsAt` into "Resets in 4h 42m" and threw the `Date` away. `UsageQuota.resetsAt` was always nil for Codex, so the menu bar fell back to parsing text, in a different format ("4h 42m" rather than "2:33") and frozen at probe time. Pace-aware status, burn rate and `percentTimeElapsed` didn't work for Codex either (#298, root cause of #218). Keep both `resetsAt` and `windowDuration` on `CodexRateLimitWindow`.
- **The primary window isn't always 5 hours.** A live `account/rateLimits/read` in 2026-09 returned `{"usedPercent":94,"windowDurationMins":10080,"resetsAt":1790500839}` as the **primary** window, which is a weekly window, and `wham/usage` on 2026-10-31 answered a Pro login with `primary_window.limit_window_seconds: 604800` and `secondary_window: null`. Pro plans have no 5-hour limit ([pricing](https://learn.chatgpt.com/docs/pricing), read 2026-10-31). So the place a window has in the answer doesn't say which one it is: each of the two rules (both sources) is named by its length, `kindByWindow` — a week or longer is *Weekly*, anything shorter *Session*, and a window the answer gives no length for takes the length its place is known for (5 hours, 7 days). Codex's own `/status` labels its rows by length the same way (`get_limits_duration` in `codex-rs/tui`: "5h limit", "Weekly limit"), so the terminal fallback, which reads those labels, already gives a Pro login only its Weekly row.
- **Plan in both modes.** `account/rateLimits/read` carries `rateLimits.planType` (`free`, `go`, `plus`, `pro`, `prolite`, `promax`, `team`, `business`, `enterprise`, `edu` and others; `PlanType` in `GetAccountRateLimitsResponse.json`), the same values as the API's `plan_type`. Both show it upper-cased as written.
- **Usage limit resets.** A Codex account can hold saved one-time resets of its usage limits; Codex's TUI lists them as *Usage limit resets* ("Full reset · Reset your current usage limits", `codex-rs/tui/src/chatwidget/usage.rs` and `reset_credits.rs`). The RPC answer's top-level `rateLimitResetCredits: {availableCount, credits?}` and `wham/usage`'s `rate_limit_reset_credits: {available_count, applicable_available_count}` say how many there are (live 2026-10-31: `available_count: 1`, `applicable_available_count: 0`). The count is not a limit — nothing is left of it and nothing refills — so it is a note, *Usage limit resets · N · available*. `0` shows; a missing or `null` summary shows nothing, since unknown isn't none. ClaudeBar never redeems one. The detail rows (`credits[]`, `GET /backend-api/wham/rate-limit-reset-credits`) and `applicable_available_count`, whose meaning upstream doesn't document, are not read.
- **No windows**: `planType == "free"` gets one "Free plan" quota at 0% used. Any other plan throws "No rate limits available yet - make some API calls first".
- **Approval flag (#259)**: Codex removed `untrusted` from `--ask-for-approval` (only `on-request` and `never` are left). An unknown value makes the CLI exit while parsing arguments, which broke the app-server *and* the TTY fallback, surfacing as "Could not find usage limits in Codex output". `never` is accepted by old and new builds and can't stall a non-interactive pipe on an approval prompt. `-s read-only` stays. Both paths share `baseArguments`.
- **TTY fallback**: when RPC throws, run `codex -s read-only -a never` with `/status\n` as input, strip ANSI codes, and within 12 lines after the "5h limit" and "Weekly limit" labels find `NN% left`. That gives no reset timestamps, so there's no countdown on this path. `data not available yet`, `update available` + `codex`, and `not logged in` / `please log in` are mapped to errors.
- **Directory-trust prompt (#267)**: Codex 0.150+ asks "Do you trust the contents of this directory?" before it does anything interactive, and it trust-checks the directory on **both** probe paths: the `app-server` RPC handshake and the TTY fallback. A probe that inherits the app's cwd (`/` from Finder/launchd) stalls until timeout, surfacing as "Could not find usage limits in Codex output". Unlike Claude, Codex 0.150 keeps trust state in SQLite with no file ClaudeBar can write, so both paths run in `Application Support/ClaudeBar/Probe` (`ProbeWorkingDirectory.resolve()`, shared with the Claude probes) and the TTY fallback auto-answers the prompt with `"1"` (the trust option's number). The answer persists once given.
- **A stalled app-server (#517)**: `codex app-server` can stop answering without exiting. With no deadline the read waited forever, the account showed *Syncing…* until the app was relaunched, and every later refresh joined the stuck one. The exchange (handshake, call and follow-ups) now has `timeout` seconds, 15 by default: at the deadline the transport is closed, which stops the app-server and ends the read, and the fetch fails with *Request timed out*, so the TTY fallback runs.
- **A login shell that doesn't finish (#550)**: before it starts `codex`, ClaudeBar asks the person's login shell where `codex` is and for its `PATH`, again every 10 minutes and on each Refresh click. That wait had no deadline and came before the exchange's, and a lookup in progress is shared, so one shell that never finished, or a program its profile started that kept its output open, held this refresh and every later one on *Syncing…* without a line in the log. The shell now has 10 seconds (`BinaryLocator.loginShellTimeout`), then it's stopped, the warning names it, and the common folders and the app's `PATH` answer; its output is read until it exits.
- **A child that outlives `SIGKILL` (#550)**: at the deadline the transport is closed: `SIGTERM`, `SIGKILL` 2 seconds later, then it waited for the exit with no limit. A reporter's sample on 0.5.15 shows that wait holding the refresh for hours, so a `codex` still there after `SIGKILL` kept every later refresh on *Syncing…*. The close now gives it 2 more seconds, then leaves it and logs `codex (pid N) was still running 2s after SIGKILL`; the refresh fails and the fallback runs. `Process` reaps its child on its own, so not waiting leaves no zombie. Why that child didn't end isn't known yet.
- **Process leak (#113)**: each refresh starts its own `app-server`. The transport the probe creates **must** be closed in a `defer`. Before this was fixed, thousands of orphaned `codex app-server` processes built up.
- **Credits are a balance in credits, with no limit (#444).** `credits: {has_credits, unlimited, balance}` (`rateLimits.credits: {hasCredits, unlimited, balance}` over RPC; `CreditsSnapshot` in `codex-rs/protocol/src/protocol.rs`) is the ChatGPT credit balance. Its unit is the credit: OpenAI's [credits overview](https://learn.chatgpt.com/docs/pricing) says "Credits are the unit used to pay for eligible usage… Credit purchase prices and applicable discounts depend on your plan or agreement", and the [Plus/Pro credits article](https://help.openai.com/en/articles/12642688) keeps them apart from the wallet, "a balance in US dollars", so a credit is not a fixed dollar amount and is never shown as money. The balance is a decimal string (live: `"62500.0000000000"` on 2026-10-31, `"59691.4837700000"` on 2026-11-02) and can go negative when a task outlives it. No limit is sent: it was once measured against a made-up 1000 and read as "$0 spent of $1,000". It is now a note named the way Codex's `/status` names it (`credit_status_row` in `codex-rs/tui/src/status/rate_limits.rs`): *Credits · Unlimited* when `unlimited`, else, when `has_credits`, the balance rounded to whole credits, *Credits · 62,500 · credits* (`"round": 0`, the header first in API mode). An account without credits (`has_credits: false`, `"balance": "0"`) shows nothing. Headers `x-codex-primary-used-percent` / `x-codex-secondary-used-percent` take precedence. Reset times always come from `rate_limit.*_window`.
- **No fallback between the modes the person picks.** Only `rpc` falls back, to the hidden `tty`. A failing `api` doesn't try `rpc`.
- **Extra buckets (#178)**: GPT-5.3-Codex-Spark (Pro research preview) has its own 5h + weekly windows, separate from the main limits. Both modes carry the data. RPC: `account/rateLimits/read` returns `result.rateLimitsByLimitId`, a map of `RateLimitSnapshot` keyed by limit id (`codex` is the main bucket and mirrors the top-level `rateLimits`; other keys are the extras). API: the body has `additional_rate_limits`, an array of `{limit_name, metered_feature, rate_limit}` where `rate_limit` is a `RateLimitStatusDetails` object that may be null and holds nested `primary_window` / `secondary_window` objects with the same `used_percent` / `reset_at` / `reset_after_seconds` fields as the main windows (plus `limit_window_seconds`, kept as the quota's `windowDuration`). Both paths append the extra quotas **after** the main session/weekly rows — the menu bar renders `quotas.first`, so the main limits must lead. Labels are trimmed for the menu (`Codex Spark` / `codex_spark` → "Spark"); the extra weekly window becomes "Spark 7d". Entries with no parseable window are skipped, and an absent map/field leaves the snapshot unchanged.
- **Passive until verified (#216)**: starting `codex app-server` or the terminal while the CLI is signed out could open the ChatGPT browser login by itself; ClaudeBar never runs `codex login`. So the default login is held back until a click: only an `.interactive` refresh (the Refresh button, Touch Bar / notch refresh, `claudebar://refresh`, a provider switch, *Test Connection*) starts Codex, and its success saves `codex.verifiedAtLeastOnce`. `.background` (the menu-bar poll) and `.passive` (opening the popover) return the last usage without starting anything, or "Codex CLI session not checked. Click Refresh or Connect to check Codex status." This is `verifyBeforeBackground` in `codex.json`, kept by `Provider`.
- **Wherever Codex keeps its login (#525)**: Codex saves its login in `auth.json` or the macOS Keychain (`cli_auth_credentials_store = "file" | "keyring" | "auto"`), so a missing `auth.json` does not mean signed out, and ClaudeBar no longer looks for it before starting the default login's RPC or terminal. Codex says it itself: signed out, `account/rateLimits/read` answers `{"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}` and `account/read` `{"account":null,"requiresOpenaiAuth":true}`, with no login started (0.157, checked on an empty `CODEX_HOME`). `codex.json` reads that answer as *Authentication required* (`jsonRpc.errors`), and because the terminal reads the same login (`fallback.sameLogin`) it is not tried, so a signed-out Codex never reaches the interactive screen. The same answer takes the background permission back (`verifiedAtLeastOnce` → false): after `codex logout` Codex is started once more at most, then held until the next click. Added accounts still require their own `auth.json`, because ClaudeBar signs them in with file storage.
- **Reasoning is already inside Codex's output (#566)**: a `token_count` event's `last_token_usage.reasoning_output_tokens` is a *part of* its `output_tokens`, not a count beside them — `total_tokens` is `input_tokens + output_tokens`, and reasoning never exceeds output (checked over 262 rollouts and 40,284 usage objects; `total == input + output` in 99.6% of them). So `codex.json` must NOT name it `tokens.reasoningOutput`, which is for a log that counts reasoning **apart** from its output (OpenCode's `tokens.reasoning`, where `total = input + output + reasoning + cache read`); naming it here would count every reasoning token twice.


## Independent Codex accounts

Additional accounts reuse `ProviderAccountConfig` and `MultiAccountSettingsRepository`.
`codex.json`'s `accounts` says how one is added and how it is signed in, once
(#577): `folder` (the default `${CODEX_HOME:-~/.codex}`, and `signedInAs` — its
`auth.json`, `id` from `$.tokens.account_id`, `email` from the ID token),
`signIn` (`codex login`), and `cli` (`CODEX_HOME` set to the folder, the other
OpenAI auth variables unset, `-c cli_auth_credentials_store="file"`). Every data
source is written once under `{{account.folder}}`; the default account fills it
with `${CODEX_HOME:-~/.codex}`. One Codex `Provider`
(the product) owns its `Account`s (the logins, [CANONICAL_MODEL](../../architecture/CANONICAL_MODEL.md#1--the-tree));
`provider.addAccount(signedInAt:)` checks a folder and adds it (`provider.signIn()` runs `codex login` into a new one first), compound ID
`codex.<local UUID>`, the default keeping `codex`. Each login is its own pill,
enable toggle and menu-bar choice — users pin two accounts at once instead of
selecting one active account within Codex.

Settings contain the email, canonical Codex directory and expected ChatGPT account
ID, never tokens. Setup rejects duplicate directories (including symlinks), the
default directory and duplicate ChatGPT account IDs. Email is a display identifier,
not an authentication key; separate workspaces can share an email.

`signedInAs.id` is checked before and after every fetch of an added account.
Every data source reads the account's own `{{account.folder}}/auth.json`; a
refreshed API token is written back only there. Every run of `codex` for an added
account — the RPC, the terminal fallback, sign-in — goes through `accounts.cli`,
so the terminal reads the folder's login too and an added account keeps the
fallback (`sameLogin` still skips it when signed out). Missing or replaced
credentials fail closed. A provider coalesces simultaneous refreshes so overlapping UI and
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
