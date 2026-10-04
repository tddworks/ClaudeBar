# ClaudeBar Architecture

This document is the **single source of truth** for ClaudeBar's architecture. All other documentation should reference this file.

## Overview

ClaudeBar is a menu bar app over a set of modules:

- **App** (`Sources/App`) — SwiftUI views that read the domain directly, and the composition root (`ClaudeBarApp`).
- **Domain** (`Sources/Domain`) — `QuotaMonitor`, the single source of truth, plus extension providers, Notify!, sessions and Usage History. It re-exports the modules.
- **Modules** (`Modules/`) — the provider engine. `Providers` runs every built-in provider from a JSON definition through one generic `Provider`; `DataSources` does each data source's lookup → fetch → mapping; `Quotas` is the usage model; `AWSClients` is the only module that links the AWS SDK; `Diagnostics` is `AppLog`.
- **Infrastructure** (`Sources/Infrastructure`) — storage (`~/.claudebar/settings.json`, the Keychain vault), notifications, hooks and the local-log analyzers behind Usage History.

Every built-in provider is data: `Modules/Providers/Resources/Providers/<id>.json` (plus a mapping script when a format needs one). No Swift names a vendor outside `AWSClients`; what a provider needs that the definition language can't say becomes a general rule in `DataSources`. How a definition runs: [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) §8.2. Which module a file goes in: [MODULAR_DESIGN.md](MODULAR_DESIGN.md). The words: [CANONICAL_MODEL.md](CANONICAL_MODEL.md).

The key principle is **QuotaMonitor as Single Source of Truth** - all provider state flows through this central actor.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ APP — ClaudeBarApp (composition root), SwiftUI views                 │
│  MenuContentView(monitor:), SettingsView, ProviderPill, cards…       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ views read the domain directly
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ DOMAIN — QuotaMonitor (@Observable, single source of truth)          │
│  AIProviders: the lineup (each login is an AIProvider)               │
│  UsageHistory, SessionMonitor, Notify!, extension providers          │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ PROVIDERS — Provider (one lifecycle: refresh, fallback, accounts)    │
│  ProviderDefinition: profile, settings, data sources, accounts       │
│  Resources/Providers/<id>.json (+ .js)  — every built-in provider    │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ DATASOURCES — DataSource: credential lookup → fetch → mapping        │
│  closed sums CredentialLookup · Fetch · Mapping, and their workers   │
│  ports: CLIExecutor, NetworkClient, RPCTransport, SecretStore,       │
│         CloudWatchClient, PriceCatalog (implemented in AWSClients)   │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ QUOTAS — UsageSnapshot, UsageQuota (Left, Window), CostUsage + lines │
│  QuotaStatus, BudgetStatus, UsageError                               │
└─────────────────────────────────────────────────────────────────────┘

INFRASTRUCTURE (implements the ports and repositories the app wires in):
  JSONSettingsRepository (+ compatibility tables), ProviderVault (Keychain),
  NotificationAlerter, hooks, ClaudeGuestPassSource
```

## Key Design Principles

### 1. Rich Domain Models

Domain models encapsulate behavior, not just data. Business logic lives in the domain layer.

```swift
// Rich domain model with computed behavior
public struct UsageQuota: Sendable, Equatable {
    public let percentRemaining: Double

    // Domain behavior - computed from state
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool { percentRemaining <= 0 }
    public var needsAttention: Bool { status.needsAttention }
}
```

**Domain-Driven Terminology** - Use domain language, not technical terms:

| Domain Term | Instead Of |
|-------------|------------|
| `UsageQuota` | `UsageData` |
| `QuotaStatus` | `HealthStatus` |
| `AIProvider` | `ServiceProvider` |
| `UsageSnapshot` | `UsageDataResponse` |
| `QuotaMonitor` | `UsageDataFetcher` |

### 2. Single Source of Truth

`QuotaMonitor` owns all provider state. Views read from it, never modify state directly.

```swift
// QuotaMonitor is the single source of truth
public actor QuotaMonitor {
    private let providers: AIProviders  // Hidden - use delegation methods

    // Delegation methods (nonisolated for UI access)
    public nonisolated var allProviders: [any AIProvider]
    public nonisolated var enabledProviders: [any AIProvider]
    public nonisolated func provider(for id: String) -> (any AIProvider)?
}
```

### 3. Settings are the definition's

A provider's settings are listed in its definition (`settings`: a kind — `secret`, `choice`, `path`, `text` — and a scope, provider or account). They are read and written through the generic `ProviderSettingsRepository` (`value`, `setValue`, `dataSourceKind`, `isOn`), kept under `<id>.<setting>` in `~/.claudebar/settings.json`; secrets go to the Keychain through `ProviderVault`. A value an older version kept elsewhere is a row in a compatibility table (`JSONSettingsRepository.legacySettingKeys` / `legacyDefaultsKeys`, `ProviderVault.legacyKeys`), never a branch, and moves the first time it's saved.

App-wide preferences, hooks and Notify! have their own repositories (`AppSettingsRepository`, `HookSettingsRepository`, `NotifySettingsRepository`), all implemented by `JSONSettingsRepository`. Two narrow sub-protocols remain for Claude's and Codex's own settings (`ClaudeSettingsRepository`, `CodexSettingsRepository`).

### 4. Protocol-Based Dependency Injection

Everything outside the process is a `@Mockable` port, so tests never touch a real CLI, network or Keychain:

```swift
@Mockable public protocol CLIExecutor: Sendable { … }        // DataSources
@Mockable public protocol NetworkClient: Sendable { … }      // DataSources
@Mockable public protocol CloudWatchClient: Sendable { … }   // DataSources, implemented in AWSClients
@Mockable public protocol PriceCatalog: Sendable { … }       // DataSources, implemented in AWSClients

// Production wiring (ClaudeBarApp):
Providers.make("bedrock", settings: settingsRepository,
               cloudWatch: AWSClients.makeCloudWatch(), priceCatalog: AWSClients.makePriceCatalog())
// Tests: DataSources.make(source, providerId:, cliExecutor: MockCLIExecutor(), network: MockNetworkClient(), …)
```

### 5. No ViewModel/AppState Layer

SwiftUI views consume `QuotaMonitor` directly. No intermediate layers.

```swift
// Views consume domain directly
struct MenuContentView: View {
    let monitor: QuotaMonitor  // Injected from app

    var body: some View {
        ForEach(monitor.enabledProviders, id: \.id) { provider in
            ProviderPill(provider: provider)
        }
    }
}
```

### 6. Chicago School TDD

Tests focus on **state changes and return values**, not method call verification.

```swift
// Good: Test state/outcome
@Test func `the api reads the session window`() async throws {
    let stub = try StubbedProvider(providerId: "acme")
    stub.answerHTTP(#"{"session":{"used_percent":30}}"#)

    let usage = try await stub.make("acme").refresh()

    #expect(usage.quota(for: .session)?.percentRemaining == 70)  // Verify the outcome
}

// Avoid: Verifying method calls (London school)
// verify(mock).someMethod().called(1)  // Don't do this
```

### 7. Real connections live behind ports

The real process runners (`DataSources/Internal/Process/`), network clients (`Internal/Network/`) and the AWS SDK (`AWSClients`) only wrap system APIs; the logic around them is tested through the ports with stubs.

## Data Flow

### Refresh Flow

```
User clicks Refresh
        │
        ▼
QuotaMonitor.refreshAll()
        │
        ▼
For each enabled login:
    provider.refresh(account)
        │
        ▼
    the active data source: credential lookup → fetch → mapping
    (a hand-off or fallback to another data source on failure)
        │
        ▼
    UsageSnapshot
        │
        ▼
    provider.snapshot = newSnapshot
        │
        ▼
SwiftUI observes change → UI updates
```

### Provider Enable/Disable Flow

```
User toggles provider in Settings
        │
        ▼
provider.isEnabled = false
        │
        ▼
didSet → settingsRepository.setEnabled(false, forProvider: id)
        │
        ▼
JSON settings file persists the change
        │
        ▼
AIProviders.enabled recomputes (filters by isEnabled)
        │
        ▼
SwiftUI observes change → provider hidden from menu
```

## File Organization

```
Modules/
├── Quotas/          # the usage model — imports nothing
├── Diagnostics/     # AppLog
├── DataSources/     # DataSource, CredentialLookup · Fetch · Mapping, workers, ports
├── AWSClients/      # the AWS SDK behind CloudWatchClient and PriceCatalog
└── Providers/
    ├── Sources/     # Provider, ProviderDefinition, Setting, accounts
    └── Resources/Providers/   # <id>.json (+ .js) — every built-in provider

Sources/
├── Domain/          # QuotaMonitor, extension providers, Notify!, sessions, Usage History
├── Infrastructure/  # storage, Keychain vault, notifications, hooks, log analyzers
└── App/             # ClaudeBarApp (composition root), SwiftUI views, settings panes
```

## Business Rules

### Quota Status Thresholds

| Remaining | Status | Needs Attention |
|-----------|--------|-----------------|
| > 50% | `.healthy` | No |
| 20-50% | `.warning` | Yes |
| < 20% | `.critical` | Yes |
| 0% | `.depleted` | Yes |

### Snapshot Freshness

- **Fresh**: < 5 minutes old
- **Stale**: >= 5 minutes old (triggers refresh)

## Adding New Features

For implementation guidance, see:
- [implement-feature skill](../../.claude/skills/implement-feature/SKILL.md) - TDD workflow
- [add-provider skill](../../.claude/skills/add-provider/SKILL.md) - Adding AI providers

## Testing Strategy

- **Provider golden tests** (`Modules/Providers/Tests`) - each definition run through the real `Provider` over stubbed connections, with real captured responses
- **Engine tests** (`Modules/DataSources/Tests`) - each general rule on a neutral fixture, never a vendor's
- **Domain and Infrastructure tests** - the monitor, settings storage and compatibility tables, notifications
- **Chicago School** - Mocks stub data, don't verify calls
