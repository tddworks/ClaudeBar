# User Behaviors Catalog

All observable user-facing behaviors in ClaudeBar, organized by feature area.
This catalog drives the **Outside-In (Double Loop)** test strategy:

- **Outer loop (BDD)**: Each behavior → Given/When/Then acceptance scenarios
- **Inner loop (TDD)**: Component-level unit tests that support the outer scenarios

```
Outer (BDD acceptance)        Inner (TDD unit)
─────────────────────         ────────────────
Behavior #9:                  ← ClaudeUsageProbeParsingTests
  User sees quota cards       ← ClaudeUsageProbeTests
  with percentage,            ← ClaudeProviderTests
  progress bar, reset time    ← QuotaStatusTests
                              ← UsageQuotaTests
```

---

## Provider Selection

| # | Behavior |
|---|----------|
| 4 | User clicks a provider pill → switches view and triggers refresh |
| 5 | Only enabled providers appear as pills |
| 6 | Disabling the currently selected provider → auto-switches to first enabled provider |
| 7 | Provider selection persists across app restarts |

### BDD Scenarios

**#4 — User clicks a provider pill → switches view and triggers refresh**
```
Scenario: Switch to a different provider
  Given Claude and Codex are both enabled
    And Claude is currently selected
  When the user selects Codex
  Then the selected provider is Codex
    And Codex quota data is refreshed
```

**#5 — Only enabled providers appear as pills**
```
Scenario: Disabled providers are hidden
  Given Claude is enabled and Codex is disabled
  When the monitor lists enabled providers
  Then only Claude appears
    And Codex is not in the list
```

**#6 — Disabling the currently selected provider → auto-switches**
```
Scenario: Disable the currently selected provider
  Given Claude is selected and Codex is enabled
  When the user disables Claude
  Then Claude is no longer selected
    And the selection switches to Codex (first enabled)

Scenario: Disable when default Claude is unavailable at startup
  Given Claude is disabled before app launch
    And Codex is enabled
  When the monitor initializes
  Then Codex is automatically selected
```

**#7 — Provider selection persists across app restarts**
```
Scenario: Selection survives restart
  Given the user selected Codex
  When the app restarts
  Then Codex is still selected
```

### Inner TDD Tests (existing)
- `QuotaMonitorTests.selectProvider updates selectedProviderId for enabled provider`
- `QuotaMonitorTests.selectProvider ignores disabled provider`
- `QuotaMonitorTests.enabledProviders returns only enabled providers`
- `QuotaMonitorTests.setProviderEnabled disables provider and updates selection`
- `QuotaMonitorTests.init selects first enabled when default claude is disabled`

---

## Quota Display

| # | Behavior |
|---|----------|
| 8 | User sees account info card (email, tier badge, "Updated 2m ago") |
| 9 | User sees quota cards with percentage, progress bar, reset time |
| 10 | User toggles "Remaining" vs "Used" display mode in settings |
| 11 | Stale data (>5 min) shows warning indicator |
| 12 | Loading state shows spinner with "Fetching usage data..." |
| 13 | Unavailable provider shows error message with guidance |
| 14 | Over-quota displays negative percentages (e.g., -98%) |

### BDD Scenarios

**#8 — User sees account info card**
```
Scenario: Account info displays after refresh
  Given Claude CLI returns output with "Account: user@example.com"
    And login method is "Claude Max"
  When the quota is refreshed
  Then the account email is "user@example.com"
    And the account tier badge shows "Claude Max"

Scenario: Account info shows data freshness
  Given the last refresh was 2 minutes ago
  When the user views the quota display
  Then the freshness label shows "Updated 2m ago"
```

**#9 — User sees quota cards with percentage, progress bar, reset time**
```
Scenario: Healthy session quota
  Given Claude CLI returns "65% left" for current session
    And reset time is "2h 15m"
  When the quota is refreshed
  Then the session card shows 65%
    And the progress bar is 65% filled
    And the status badge shows "Healthy"
    And the reset label shows "Resets in 2h 15m"

Scenario: Multiple quota types displayed
  Given Claude CLI returns session (65%), weekly (35%), and opus (80%) quotas
  When the quota is refreshed
  Then 3 quota cards are displayed
    And each has its own percentage, progress bar, and reset time
```

**#10 — User toggles "Remaining" vs "Used" display mode**
```
Scenario: Switch to "Used" display
  Given the display mode is "Remaining"
    And session quota is 65% remaining
  When the user switches to "Used" mode
  Then the card shows "35% Used" instead of "65% Remaining"
    And the progress bar shows 35% filled (inverted)
```

**#13 — Unavailable provider shows error message**
```
Scenario: CLI not installed
  Given Claude CLI is not found on the system
  When the user views Claude
  Then an error message shows "Claude Unavailable"
    And guidance text explains how to install

Scenario: Session expired
  Given Claude API returns a 401 error
  When the quota refresh fails
  Then the error message shows "Session expired. Run `claude` in terminal to log in again"
```

**#14 — Over-quota displays negative percentages**
```
Scenario: User exceeds quota limit
  Given Copilot usage is 99 of 50 requests (manual override)
  When the quota is calculated
  Then the percentage shows -98%
    And the status is "Depleted"
```

### Inner TDD Tests (existing)
- `ClaudeUsageProbeParsingTests.parses session quota from left format`
- `ClaudeUsageProbeParsingTests.parses used format as remaining`
- `ClaudeUsageProbeParsingTests.parses account email and tier`
- `ClaudeUsageProbeTests.probe extracts account type from usage output`
- `QuotaStatusTests.healthy status for percentage above 50`
- `QuotaStatusTests.depleted status for zero or negative percentage`
- `UsageQuotaTests.displayPercent returns correct value for remaining/used`
- `UsageDisplayModeTests.*`

---

## Refresh

| # | Behavior |
|---|----------|
| 15 | User clicks Refresh → fetches latest quota for current provider |
| 16 | Button shows "Syncing..." spinner while in progress |
| 17 | Duplicate refresh clicks are ignored while syncing |
| 18 | Background sync auto-refreshes at configured interval |

### BDD Scenarios

**#15 — User clicks Refresh → fetches latest quota**
```
Scenario: Successful refresh
  Given Claude is selected and available
  When the user clicks Refresh
  Then the quota snapshot is updated with fresh data

Scenario: Refresh with provider error
  Given Codex probe throws a timeout error
  When the user clicks Refresh
  Then the error is stored on the provider
    And other providers are not affected
```

**#17 — Duplicate refresh clicks are ignored**
```
Scenario: Provider already syncing
  Given Claude is currently refreshing (isSyncing = true)
  When the user clicks Refresh again
  Then no additional refresh is triggered
```

**#18 — Background sync auto-refreshes**
```
Scenario: Continuous monitoring
  Given background sync is enabled with 100ms interval
  When monitoring starts
  Then refresh events are emitted at the configured interval
    And monitoring stops when requested
```

### Inner TDD Tests (existing)
- `QuotaMonitorTests.monitor can refresh a provider by ID`
- `QuotaMonitorTests.one provider failure does not affect others`
- `QuotaMonitorTests.monitor can start continuous monitoring`
- `QuotaMonitorTests.monitor stops when requested`
- `QuotaMonitorTests.isRefreshing returns false when no providers syncing`
- `ClaudeProviderTests.isSyncing is true during refresh`
- `CodexProviderTests.stores snapshot after refresh`

---

## Notifications

| # | Behavior |
|---|----------|
| 19 | Quota drops to Warning (≤50%) → system notification |
| 20 | Quota drops to Critical (<20%) → system notification |
| 21 | Quota hits Depleted (0%) → system notification |
| 22 | Quota improves → no notification (only degrades trigger alerts) |
| 23 | App requests notification permission on first launch |

### BDD Scenarios

**#19–21 — Quota degrades → system notification**
```
Scenario: Quota drops from healthy to critical
  Given Claude was previously at 70% (healthy)
  When a refresh returns 15% (critical)
  Then the alerter is called with previousStatus=healthy, currentStatus=critical

Scenario: Quota drops from healthy to warning
  Given Claude was previously at 70% (healthy)
  When a refresh returns 40% (warning)
  Then a warning notification is sent
```

**#22 — Quota improves → no notification**
```
Scenario: Quota stays healthy
  Given Claude is at 70% (healthy)
  When a refresh returns 70% (healthy)
  Then no notification is sent
```

### Inner TDD Tests (existing)
- `QuotaMonitorTests.alerter is called on status change`
- `QuotaMonitorTests.alerter not called when status unchanged`
- `NotificationAlerterTests.*`
- `QuotaStatusTests.from(percentRemaining:) thresholds`

---

## Menu Bar

| # | Behavior |
|---|----------|
| 1 | User clicks menu bar icon → sees popup with provider pills, quota cards, action bar |
| 2 | Menu bar icon reflects the selected provider's worst quota status (healthy/warning/critical/depleted) |
| 3 | Menu bar icon appearance changes with selected theme |

### BDD Scenarios

**#2 — Menu bar icon reflects worst quota status**
```
Scenario: Overall status is worst across providers
  Given Claude is at 70% (healthy) and Codex is at 15% (critical)
  When overall status is calculated
  Then the overall status is "critical" (worst wins)

Scenario: Disabled provider does not affect overall status
  Given Claude is at 70% (healthy)
    And Codex is at 5% (critical) but disabled
  When overall status is calculated
  Then the overall status is "healthy" (disabled providers excluded)
```

### Inner TDD Tests (existing)
- `QuotaMonitorTests.monitor calculates overall status from all providers`
- `QuotaMonitorTests.overallStatus only considers enabled providers`
- `QuotaStatusTests.max of multiple statuses returns worst status`

---

## Action Bar

| # | Behavior |
|---|----------|
| 24 | User clicks Dashboard → opens provider's web dashboard in browser |
| 25 | User clicks Share (Claude only) → shows referral link overlay with pass count |
| 26 | Settings button shows red badge when app update available |
| 27 | User clicks Quit → app terminates |

### BDD Scenarios

**#24 — Dashboard opens correct URL per provider**
```
Scenario: Open Claude dashboard
  Given Claude is the selected provider
  When the user clicks Dashboard
  Then the browser opens "https://console.anthropic.com/settings/billing"

Scenario: Provider with no dashboard
  Given Antigravity is selected (local-only, no dashboard)
  When the user views the action bar
  Then the Dashboard button is hidden
```

**#25 — Share Claude Code guest passes**
```
Scenario: Share referral link
  Given Claude is selected
    And `claude /passes` returns a referral URL with 3 passes left
  When the user clicks Share
  Then the overlay shows the referral link
    And shows "3 passes left"
```

### Inner TDD Tests (existing)
- `ClaudePassProbeTests.*`
- `ClaudeProviderTests.fetchPasses stores guest pass data`

---

## Claude Configuration

| # | Behavior |
|---|----------|
| 28 | User switches Claude to API mode → uses OAuth HTTP API instead of CLI |
| 29 | API mode shows credential status (found / not found) |
| 30 | Expired session shows "Run `claude` in terminal to log in again" |
| 31 | User sets monthly budget → sees cost-based usage card |
| 32 | Auto-trusts probe directory when CLI shows trust dialog |

### BDD Scenarios

**#28 — Switch Claude to API mode**
```
Scenario: Switch from CLI to API mode
  Given Claude is using CLI mode (default)
    And OAuth credentials exist at ~/.claude/.credentials.json
  When the user switches to API mode
  Then the probe mode is persisted as "api"
    And the next refresh uses the API probe instead of CLI

Scenario: API mode falls back when no credentials
  Given the user selects API mode
    But no OAuth credentials are found
  When the probe checks availability
  Then the credential status shows "No OAuth credentials found"
```

**#30 — Expired session error**
```
Scenario: API returns 401
  Given Claude is using API mode
  When the API returns HTTP 401
  Then the error message shows "Session expired. Run `claude` in terminal to log in again"
```

### Inner TDD Tests (existing)
- `ClaudeAPIUsageProbeTests.*`
- `ClaudeCredentialLoaderTests.*`
- `ClaudeProviderTests.probeMode switching`
- `ProbeErrorTests.sessionExpired description`

---

## Codex Configuration

| # | Behavior |
|---|----------|
| 33 | User switches Codex to API mode → uses ChatGPT backend API instead of RPC |
| 34 | API mode shows credential status (found / not found) |

### BDD Scenarios

**#33 — Switch Codex to API mode**
```
Scenario: Switch from RPC to API mode
  Given Codex is using RPC mode (default)
    And OAuth credentials exist at ~/.codex/auth.json
  When the user switches to API mode
  Then the probe mode is persisted as "api"
    And the next refresh uses the API probe

Scenario: API mode unavailable without credentials
  Given no credentials exist at ~/.codex/auth.json
  When the user views Codex configuration
  Then the credential status shows "No OAuth credentials found"
```

### Inner TDD Tests (existing)
- `CodexAPIUsageProbeTests.*`
- `CodexCredentialLoaderTests.*`
- `CodexUsageProbeTests.*`

---

## Copilot Configuration

| # | Behavior |
|---|----------|
| 35 | User enters GitHub PAT + username → Copilot quota fetched via API |
| 36 | User sets plan tier (Free/Pro/Business/Enterprise/Pro+) → adjusts monthly limit |
| 37 | User enables manual override → enters usage count or percentage |
| 38 | API returns empty → warning banner suggests manual entry |
| 39 | "Save & Test Connection" validates token |
| 40 | Manual usage auto-clears when billing period changes |

### BDD Scenarios

**#35 — Copilot authentication**
```
Scenario: Valid GitHub token
  Given the user enters a valid PAT and username
  When Copilot probe fetches usage
  Then premium request usage is displayed

Scenario: Token from environment variable
  Given the user sets GITHUB_TOKEN as the auth env var
    And GITHUB_TOKEN is set in the environment
  When the probe authenticates
  Then the environment variable token is used
```

**#37 — Manual usage override**
```
Scenario: Enter request count
  Given the user enables manual override
  When they enter "99" as the usage value
    And the monthly limit is 50 (Free/Pro)
  Then the quota shows -98% remaining

Scenario: Enter percentage
  Given the user enables manual override
  When they enter "198%" as the usage value
  Then the quota shows -98% remaining
```

**#40 — Manual usage auto-clears on period change**
```
Scenario: Billing period rolls over
  Given the user entered manual usage in January
  When the billing period changes to February
  Then the manual usage value is cleared
```

### Inner TDD Tests (existing)
- `CopilotUsageProbeTests.*`
- `CopilotProviderTests.*`

---

## Z.ai Configuration

| # | Behavior |
|---|----------|
| 41 | User sets custom config path → probe reads from that file |
| 42 | User sets env var fallback → probe uses env var if config file has no token |

### BDD Scenarios

**#41 — Custom config path**
```
Scenario: Custom config file path
  Given the user sets config path to "/custom/settings.json"
    And that file contains a ZHIPU endpoint with API key
  When the probe checks availability
  Then it reads from "/custom/settings.json"
    And returns true
```

**#42 — Environment variable fallback**
```
Scenario: Env var used when config has no token
  Given the config file has no API key
    And the user set GLM_AUTH_TOKEN as the env var
    And GLM_AUTH_TOKEN is set in the environment
  When the probe authenticates
  Then the env var token is used

Scenario: No config and no env var
  Given the config file has no API key
    And no env var is configured
  When the probe checks
  Then it throws authenticationRequired
```

### Inner TDD Tests (existing)
- `ZaiUsageProbeTests.*`
- `ZaiUsageProbeParsingTests.*`
- `ZaiUsageProbeEnvVarFallbackTests.*`
- `ZaiProviderTests.*`

---

## Bedrock Configuration

| # | Behavior |
|---|----------|
| 43 | User sets AWS profile → probe authenticates with that SSO profile |
| 44 | User sets regions → probe queries CloudWatch across those regions |
| 45 | User sets daily budget → shows budget progress bar |

### BDD Scenarios

**#43 — AWS profile authentication**
```
Scenario: SSO profile configured
  Given the user sets AWS profile to "my-sso-profile"
  When Bedrock probe authenticates
  Then it uses SSOAWSCredentialIdentityResolver with "my-sso-profile"
```

**#44 — Multi-region monitoring**
```
Scenario: Multiple regions
  Given the user sets regions to "us-east-1, us-west-2"
  When the probe queries CloudWatch
  Then it fetches metrics from both regions
    And aggregates costs and tokens
```

**#45 — Daily budget tracking**
```
Scenario: Budget configured
  Given the user sets daily budget to $50
    And today's usage is $35
  When the quota is displayed
  Then the budget progress shows 70% used
```

### Inner TDD Tests (existing)
- `BedrockUsageProbeTests.*`

---

## Provider Enable/Disable

| # | Behavior |
|---|----------|
| 46 | User toggles provider off → removed from pills, excluded from monitoring |
| 47 | User toggles provider on → appears in pills, included in monitoring |
| 48 | Enabled state persists across restarts |

### BDD Scenarios

**#46 — Disable a provider**
```
Scenario: Disable provider excludes from refresh
  Given Claude and Codex are both enabled
  When the user disables Codex
  Then refreshAll skips Codex
    And only Claude is refreshed

Scenario: Disabled provider excluded from overall status
  Given Claude is healthy and Codex is critical
  When the user disables Codex
  Then the overall status is "healthy"
```

**#47 — Enable a provider**
```
Scenario: Enable provider without changing selection
  Given Claude is selected and Codex is disabled
  When the user enables Codex
  Then Codex appears in the enabled list
    And Claude remains selected
```

### Inner TDD Tests (existing)
- `QuotaMonitorTests.refreshAll skips disabled providers`
- `QuotaMonitorTests.overallStatus only considers enabled providers`
- `QuotaMonitorTests.setProviderEnabled disables provider and updates selection`
- `QuotaMonitorTests.setProviderEnabled enables provider without changing selection`
- `UserDefaultsProviderSettingsRepositoryTests.*`

---

## Themes

| # | Behavior |
|---|----------|
| 49 | User selects Dark/Light/CLI/Christmas theme → UI updates immediately |
| 50 | System theme follows macOS light/dark mode |
| 51 | Christmas theme auto-enables Dec 24–26, reverts after |

### BDD Scenarios

**#49 — Theme selection**
```
Scenario: Switch to CLI theme
  Given the current theme is Dark
  When the user selects CLI theme
  Then the font design changes to monospaced
    And accent colors change to green/amber
```

**#51 — Seasonal auto-theme**
```
Scenario: Christmas auto-enable
  Given the date is December 25
    And the user hasn't explicitly chosen a theme
  When the app launches
  Then the Christmas theme is active
    And snowfall effect is visible
```

### Inner TDD Tests (existing)
- Theme tests (if any) for theme registry and mode switching

---

## Updates

| # | Behavior |
|---|----------|
| 52 | App checks for updates when menu opens |
| 53 | User toggles beta channel → receives pre-release updates |
| 54 | User clicks manual check → shows available version or "up to date" |

### BDD Scenarios

**#53 — Beta channel**
```
Scenario: Opt into beta updates
  Given the user enables "Receive beta updates"
  When Sparkle checks for updates
  Then it includes pre-release versions in the appcast
```

### Inner TDD Tests (existing)
- Update channel handling tests (17 scenarios per CHANGELOG)

---

## Coverage Summary

| Feature Area | Behaviors | BDD Scenarios | Inner TDD Coverage |
|---|---|---|---|
| Provider Selection | 4–7 | 5 | Strong (QuotaMonitorTests) |
| Quota Display | 8–14 | 7 | Strong (Parsing + ProbeTests + StatusTests) |
| Refresh | 15–18 | 5 | Strong (MonitorTests + ProviderTests) |
| Notifications | 19–23 | 3 | Moderate (AlerterTests + MonitorTests) |
| Menu Bar | 1–3 | 2 | Moderate (overallStatus tests) |
| Action Bar | 24–27 | 3 | Partial (PassProbe, no dashboard URL tests) |
| Claude Config | 28–32 | 4 | Strong (API + Credential + Provider tests) |
| Codex Config | 33–34 | 2 | Strong (API + Credential tests) |
| Copilot Config | 35–40 | 5 | Moderate (ProbeTests + ProviderTests) |
| Z.ai Config | 41–42 | 4 | Strong (Probe + EnvVar + Provider tests) |
| Bedrock Config | 43–45 | 3 | Partial (ProbeTests only) |
| Provider Enable | 46–48 | 4 | Strong (MonitorTests + SettingsTests) |
| Themes | 49–51 | 2 | Weak (no dedicated theme tests) |
| Updates | 52–54 | 1 | Moderate (channel tests) |
| **Total** | **54** | **50** | |
