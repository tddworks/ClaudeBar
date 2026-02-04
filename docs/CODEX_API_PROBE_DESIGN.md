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