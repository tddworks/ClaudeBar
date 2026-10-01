# AWS Bedrock Provider Design

**Date:** 2026-01-22
**Status:** Ready for Implementation
**Author:** Tom Stetson + Claude

## Overview

Add AWS Bedrock as a new provider to ClaudeBar, enabling users to monitor their Bedrock usage and costs directly from the menu bar. This provider will query AWS CloudWatch for usage metrics, calculate costs using cached pricing data from the AWS Pricing API, and display budget-focused information with per-model breakdowns.

### Goals

1. **Full Bedrock support** - Track all Bedrock models (Claude, Mistral, Llama, etc.)
2. **Global community** - Support any AWS account, region, and common auth methods
3. **Cost visibility** - Show real-time cost estimates with budget tracking
4. **Pattern compliance** - Match ClaudeBar's existing architecture and UI patterns exactly

### Non-Goals

- Historical trend analysis (not in current ClaudeBar)
- Multi-account switching (not in current ClaudeBar)
- Custom pricing agreements (use AWS Pricing API only)

---

## Architecture

### Provider Hierarchy

```
ClaudeBar Providers
├── ClaudeProvider (existing)
├── CodexProvider (existing)
├── GeminiProvider (existing)
├── CopilotProvider (existing)
├── AntigravityProvider (existing)
├── ZaiProvider (existing)
└── BedrockProvider (NEW)
```

Bedrock is a **peer provider**, not a sub-type of Claude. It appears as its own pill in the UI.

### Layer Responsibilities

```
┌─────────────────────────────────────────────────────────────────────┐
│                            App Layer                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ MenuContentView │  │ ProviderPill    │  │ BedrockDetailView   │  │
│  │ (existing)      │  │ (existing)      │  │ (NEW - expandable)  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                           Domain Layer                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ BedrockProvider │  │ BedrockUsage    │  │ BedrockModel        │  │
│  │ (NEW)           │  │ (NEW)           │  │ (NEW)               │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
│                                                                      │
│  Reused: UsageSnapshot, CostUsage, QuotaStatus, BudgetStatus        │
├─────────────────────────────────────────────────────────────────────┤
│                       Infrastructure Layer                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ BedrockUsage    │  │ BedrockPricing  │  │ BedrockSettings     │  │
│  │ Probe (NEW)     │  │ Service (NEW)   │  │ Repository (NEW)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘  │
│                                                                      │
│  External: AWS SDK for Swift (CloudWatch, Pricing, STS)             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Domain Models

### BedrockModel

Represents a single Bedrock model with metadata for display and pricing.

```swift
/// Metadata for a Bedrock model
public struct BedrockModel: Sendable, Equatable, Hashable, Identifiable {
    /// Raw AWS model ID (e.g., "us.anthropic.claude-opus-4-5-20251101-v1:0")
    public let modelId: String

    /// Provider name parsed from modelId (e.g., "Anthropic")
    public let provider: String

    /// Friendly display name (e.g., "Claude Opus 4.5")
    public let displayName: String

    /// Pricing per 1M input tokens (USD)
    public let inputPricePer1M: Decimal

    /// Pricing per 1M output tokens (USD)
    public let outputPricePer1M: Decimal

    public var id: String { modelId }
}
```

### BedrockModelUsage

Usage statistics for a single model.

```swift
/// Usage data for a single Bedrock model
public struct BedrockModelUsage: Sendable, Equatable {
    /// The model this usage is for
    public let model: BedrockModel

    /// Number of API invocations
    public let invocations: Int

    /// Total input tokens consumed
    public let inputTokens: Int

    /// Total output tokens generated
    public let outputTokens: Int

    /// Calculated cost based on model pricing
    public var estimatedCost: Decimal {
        let inputCost = Decimal(inputTokens) / 1_000_000 * model.inputPricePer1M
        let outputCost = Decimal(outputTokens) / 1_000_000 * model.outputPricePer1M
        return inputCost + outputCost
    }
}
```

### BedrockUsageSummary

Aggregate usage across all models (stored in `UsageSnapshot.costUsage`).

```swift
/// Extended usage data for Bedrock (embedded in CostUsage or separate)
public struct BedrockUsageSummary: Sendable, Equatable {
    /// Per-model usage breakdown
    public let modelUsages: [BedrockModelUsage]

    /// AWS region this data is from
    public let region: String

    /// Time period for this data
    public let period: BedrockTimePeriod

    /// Total cost across all models
    public var totalCost: Decimal {
        modelUsages.reduce(0) { $0 + $1.estimatedCost }
    }

    /// Total invocations across all models
    public var totalInvocations: Int {
        modelUsages.reduce(0) { $0 + $1.invocations }
    }

    /// Models grouped by provider for UI display
    public var byProvider: [String: [BedrockModelUsage]] {
        Dictionary(grouping: modelUsages, by: { $0.model.provider })
    }
}

public enum BedrockTimePeriod: String, Sendable {
    case today = "TODAY"
    case monthToDate = "MTD"
}
```

---

## Infrastructure Components

### BedrockUsageProbe

Queries CloudWatch for Bedrock metrics.

```swift
/// Probes AWS CloudWatch for Bedrock usage metrics
public final class BedrockUsageProbe: UsageProbe, @unchecked Sendable {
    private let cloudWatchClient: CloudWatchClient
    private let pricingService: BedrockPricingService
    private let settingsRepository: BedrockSettingsRepository

    public init(
        cloudWatchClient: CloudWatchClient? = nil,
        pricingService: BedrockPricingService,
        settingsRepository: BedrockSettingsRepository
    ) {
        // Initialize AWS client with configured profile/region
    }

    public func isAvailable() async -> Bool {
        // Check if AWS credentials are configured and valid
        // Try a simple STS GetCallerIdentity call
    }

    public func probe() async throws -> UsageSnapshot {
        // 1. Get configured regions from settings
        // 2. Query CloudWatch for each region
        // 3. Aggregate metrics by ModelId
        // 4. Look up pricing for each model
        // 5. Calculate costs
        // 6. Build UsageSnapshot with CostUsage
    }
}
```

#### CloudWatch Query Strategy

```swift
// Metrics to query (all have ModelId dimension)
let metrics = [
    "Invocations",
    "InputTokenCount",
    "OutputTokenCount"
]

// Time period: midnight today to now (UTC)
let startTime = Calendar.current.startOfDay(for: Date())
let endTime = Date()

// Query pattern for each metric
func queryMetric(_ metricName: String) async throws -> [ModelMetricData] {
    let request = GetMetricStatisticsInput(
        namespace: "AWS/Bedrock",
        metricName: metricName,
        startTime: startTime,
        endTime: endTime,
        period: 86400,  // Daily granularity
        statistics: [.sum],
        dimensions: nil  // Get all ModelIds
    )
    // Parse response, group by ModelId dimension
}
```

### BedrockPricingService

Fetches and caches model pricing from AWS Pricing API.

```swift
/// Manages Bedrock model pricing with aggressive caching
public final class BedrockPricingService: @unchecked Sendable {
    private let pricingClient: PricingClient
    private let settingsRepository: BedrockSettingsRepository
    private let cache: BedrockPricingCache

    /// Cache refresh interval (24 hours)
    private let cacheMaxAge: TimeInterval = 86400

    public func getPricing(for modelId: String) async throws -> BedrockModel {
        // 1. Check cache first
        if let cached = cache.get(modelId), !cached.isStale {
            return cached.model
        }

        // 2. Fetch from AWS Pricing API (or use bundled defaults)
        let pricing = try await fetchPricing(for: modelId)

        // 3. Update cache
        cache.set(modelId, pricing)

        return pricing
    }

    public func refreshAllPricing() async throws {
        // Called on app launch if cache is >24h old
        // Fetches pricing for all known Bedrock models
    }
}

/// UserDefaults-backed pricing cache
final class BedrockPricingCache {
    private let userDefaults: UserDefaults
    private let lastRefreshKey = "bedrock.pricing.lastRefresh"
    private let pricingDataKey = "bedrock.pricing.data"

    var isStale: Bool {
        guard let lastRefresh = userDefaults.object(forKey: lastRefreshKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) > 86400
    }
}
```

#### Bundled Default Pricing

Ship with static pricing as fallback (updated via PRs):

```swift
/// Default pricing bundled with the app (fallback if API unavailable)
enum BedrockDefaultPricing {
    static let models: [String: (input: Decimal, output: Decimal)] = [
        // Anthropic Claude
        "anthropic.claude-opus-4-5-20251101-v1:0": (15.00, 75.00),
        "anthropic.claude-sonnet-4-5-20250929-v1:0": (3.00, 15.00),
        "anthropic.claude-haiku-4-5-20251001-v1:0": (0.25, 1.25),

        // Mistral
        "mistral.mistral-large-3-675b-instruct": (2.00, 6.00),

        // Amazon
        "amazon.nova-pro-v1:0": (0.80, 3.20),

        // ... more models
    ]
}
```

### BedrockSettingsRepository

Extends `ProviderSettingsRepository` for Bedrock-specific settings.

```swift
/// Bedrock-specific settings (extends base ProviderSettingsRepository)
public protocol BedrockSettingsRepository: ProviderSettingsRepository {
    // AWS Profile
    func awsProfile() -> String
    func setAwsProfile(_ profile: String)

    // Regions to monitor
    func regions() -> [String]
    func setRegions(_ regions: [String])

    // Budget settings
    func dailyBudget() -> Decimal?
    func setDailyBudget(_ budget: Decimal?)

    func monthlyBudget() -> Decimal?
    func setMonthlyBudget(_ budget: Decimal?)

    // Pricing cache
    func lastPricingRefresh() -> Date?
    func setLastPricingRefresh(_ date: Date)

    func cachedPricing() -> Data?
    func setCachedPricing(_ data: Data)
}
```

Implementation in `UserDefaultsProviderSettingsRepository`:

```swift
extension UserDefaultsProviderSettingsRepository: BedrockSettingsRepository {
    private enum BedrockKeys {
        static let awsProfile = "bedrock.awsProfile"
        static let regions = "bedrock.regions"
        static let dailyBudget = "bedrock.dailyBudget"
        static let monthlyBudget = "bedrock.monthlyBudget"
        static let lastPricingRefresh = "bedrock.pricing.lastRefresh"
        static let cachedPricing = "bedrock.pricing.cache"
    }

    public func awsProfile() -> String {
        userDefaults.string(forKey: BedrockKeys.awsProfile) ?? ""
    }

    public func setAwsProfile(_ profile: String) {
        userDefaults.set(profile, forKey: BedrockKeys.awsProfile)
    }

    // ... other implementations
}
```

---

## BedrockProvider

The main provider class following ClaudeBar patterns.

```swift
/// AWS Bedrock provider - monitors usage via CloudWatch
@Observable
public final class BedrockProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity

    public let id: String = "bedrock"
    public let name: String = "Bedrock"
    public let cliCommand: String = "aws"  // For availability check

    public var dashboardURL: URL? {
        // Link to AWS Bedrock console for configured region
        guard let region = settingsRepository.regions().first else {
            return URL(string: "https://console.aws.amazon.com/bedrock/")
        }
        return URL(string: "https://\(region).console.aws.amazon.com/bedrock/")
    }

    public var statusPageURL: URL? {
        URL(string: "https://health.aws.amazon.com/")
    }

    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    /// Detailed usage breakdown (beyond what CostUsage holds)
    public private(set) var usageSummary: BedrockUsageSummary?

    // MARK: - Dependencies

    private let probe: BedrockUsageProbe
    private let settingsRepository: BedrockSettingsRepository

    // MARK: - Initialization

    public init(
        probe: BedrockUsageProbe,
        settingsRepository: BedrockSettingsRepository
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "bedrock")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil

            // Extract detailed summary if available
            // (stored as associated data or parsed from snapshot)

            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }
}
```

---

## AWS Authentication

### Supported Methods

1. **Environment variables** - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
2. **Credential file** - `~/.aws/credentials` with profile selection
3. **SSO profiles** - `~/.aws/config` with SSO configuration

### Implementation

```swift
/// AWS credential resolution for Bedrock
final class BedrockAWSCredentialResolver {
    private let settingsRepository: BedrockSettingsRepository

    /// Resolves AWS credentials based on user configuration
    func resolveCredentials() async throws -> AWSCredentials {
        let profile = settingsRepository.awsProfile()

        if profile.isEmpty {
            // Use default credential chain (env vars → default profile → instance role)
            return try await AWSCredentials.default()
        } else {
            // Use specific profile
            return try await AWSCredentials.profile(named: profile)
        }
    }

    /// Lists available AWS profiles from ~/.aws/config
    func availableProfiles() -> [String] {
        // Parse ~/.aws/config for [profile X] sections
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")

        guard let content = try? String(contentsOf: configPath) else {
            return []
        }

        // Regex to extract profile names
        let pattern = #"\[profile\s+([^\]]+)\]"#
        // ... parse and return profile names
    }
}
```

### Security Model

| What We Store | Where | Security |
|---------------|-------|----------|
| Profile name (string) | UserDefaults | Not sensitive |
| Region preferences | UserDefaults | Not sensitive |
| Budget settings | UserDefaults | Not sensitive |
| Pricing cache | UserDefaults | Not sensitive |
| **Actual credentials** | **NEVER** | AWS SDK handles |

The AWS SDK for Swift reads credentials from standard locations. We never touch them.

---

## UI Design

### Provider Pill

Bedrock appears as a new pill alongside existing providers:

```
[ Claude ] [ Bedrock ] [ Codex ] [ Gemini ] [ Copilot ] ...
```

Icon: `cloud.fill` (SF Symbol) or custom AWS/Bedrock icon in Assets.

### Main Card (Budget-Focused)

```
┌─────────────────────────────────────────────────────────────┐
│  ☁️ AWS Bedrock                              [AWS Account]  │
│     us-east-1 · Today                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ DAILY BUDGET                              [Warning]  │   │
│  │                                                      │   │
│  │  $57.30                                             │   │
│  │  ────────────────────────── $100.00                 │   │
│  │  ████████████████░░░░░░░░░  57% used                │   │
│  │                                                      │   │
│  │  ⏱ Resets at midnight UTC                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ▶ Model Breakdown (4 models)                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Expanded Model Breakdown

When user clicks "Model Breakdown":

```
┌─────────────────────────────────────────────────────────────┐
│  ▼ Model Breakdown                                          │
│                                                             │
│  Anthropic                                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Claude Opus 4.5              $52.30         (91%)   │   │
│  │ 1.07M input · 547K output · 1,939 calls             │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Claude Haiku 4.5              $0.45          (1%)   │   │
│  │ 45K input · 12K output · 23 calls                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Mistral                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Mistral Large                 $4.55          (8%)   │   │
│  │ 890K input · 234K output · 156 calls                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Hover on model name shows raw ModelId in tooltip.

### Settings Section

New section in SettingsView for Bedrock configuration:

```
┌─────────────────────────────────────────────────────────────┐
│  AWS Bedrock Settings                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  AWS Profile                                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ my-aws-profile                                  ▼   │   │
│  └─────────────────────────────────────────────────────┘   │
│  ℹ️ Credentials read from ~/.aws - not stored by ClaudeBar  │
│                                                             │
│  Regions                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ☑ us-east-1 (default)                               │   │
│  │ ☐ us-west-2                                         │   │
│  │ ☐ eu-west-1                                         │   │
│  │ + Add region...                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Daily Budget                                               │
│  ┌──────────────┐                                          │
│  │ $100.00      │  ☑ Enable alerts                        │
│  └──────────────┘                                          │
│                                                             │
│  Monthly Budget                                             │
│  ┌──────────────┐                                          │
│  │ $2,000.00    │  ☑ Enable alerts                        │
│  └──────────────┘                                          │
│                                                             │
│  Pricing Data                                               │
│  Last updated: 2 hours ago                    [↻ Refresh]   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Alerts

### QuotaStatus Mapping for Budget-Based Providers

Since Bedrock uses budgets (not quotas), we map budget usage to QuotaStatus:

```swift
extension BudgetStatus {
    /// Maps budget percentage to QuotaStatus for alerting
    var quotaStatus: QuotaStatus {
        let percentRemaining = 100 - percentUsed
        return QuotaStatus.from(percentRemaining: percentRemaining)
    }
}
```

This means:
- **<50% budget used** → healthy (no alert)
- **50-80% budget used** → warning (⚠️ alert)
- **80-100% budget used** → critical (🔴 alert)
- **>100% budget used** → depleted (💀 alert)

Alerts use existing `NotificationAlerter` infrastructure:

```swift
// In QuotaMonitor.handleSnapshotUpdate
if let budgetStatus = snapshot.costUsage?.budgetStatusFromBuiltIn {
    let newStatus = budgetStatus.quotaStatus
    // ... existing alert logic applies
}
```

---

## Error Handling

### ProbeError Extensions

```swift
extension ProbeError {
    // Bedrock-specific errors
    static let awsCredentialsNotFound = ProbeError.executionFailed(
        "AWS credentials not found. Configure via AWS CLI or environment variables."
    )

    static let awsAccessDenied = ProbeError.executionFailed(
        "Access denied. Ensure your IAM user has cloudwatch:GetMetricStatistics permission."
    )

    static let bedrockNotEnabled = ProbeError.executionFailed(
        "Bedrock not enabled in this region. Check AWS Console."
    )

    static let regionNotSupported = ProbeError.executionFailed(
        "Bedrock is not available in the configured region."
    )
}
```

### Empty State Handling

When Bedrock is enabled but:
- No credentials: Show setup instructions
- No usage today: Show "$0.00" with "No Bedrock usage today"
- API error: Show error with retry button

---

## Testing Strategy

### Domain Tests

```swift
// BedrockModelUsageTests.swift
func test_estimatedCost_calculatesCorrectly() {
    let model = BedrockModel(
        modelId: "anthropic.claude-opus-4-5",
        provider: "Anthropic",
        displayName: "Claude Opus 4.5",
        inputPricePer1M: 15.00,
        outputPricePer1M: 75.00
    )

    let usage = BedrockModelUsage(
        model: model,
        invocations: 100,
        inputTokens: 1_000_000,
        outputTokens: 500_000
    )

    // 1M input × $15 + 0.5M output × $75 = $15 + $37.50 = $52.50
    XCTAssertEqual(usage.estimatedCost, 52.50)
}
```

### Infrastructure Tests

```swift
// BedrockUsageProbeTests.swift
func test_probe_parsesCloudWatchResponse() async throws {
    let mockCloudWatch = MockCloudWatchClient()
    mockCloudWatch.stubbedResponse = cloudWatchFixture("bedrock_metrics.json")

    let probe = BedrockUsageProbe(
        cloudWatchClient: mockCloudWatch,
        pricingService: mockPricingService,
        settingsRepository: mockSettings
    )

    let snapshot = try await probe.probe()

    XCTAssertEqual(snapshot.providerId, "bedrock")
    XCTAssertNotNil(snapshot.costUsage)
    XCTAssertEqual(snapshot.costUsage?.totalCost, 57.30)
}
```

### Integration Tests

Manual testing checklist:
- [ ] Fresh install with no AWS credentials
- [ ] Valid credentials, no Bedrock usage
- [ ] Valid credentials, with usage across multiple models
- [ ] SSO profile authentication
- [ ] Region switching
- [ ] Budget alerts trigger correctly
- [ ] Pricing cache refresh

---

## Dependencies

### New Package Dependencies

Add to `Package.swift`:

```swift
dependencies: [
    // Existing dependencies...

    // AWS SDK for Swift
    .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
],
targets: [
    .target(
        name: "Infrastructure",
        dependencies: [
            "Domain",
            .product(name: "AWSCloudWatch", package: "aws-sdk-swift"),
            .product(name: "AWSPricing", package: "aws-sdk-swift"),
            .product(name: "AWSSTS", package: "aws-sdk-swift"),
        ]
    ),
]
```

### AWS SDK Services Used

| Service | Purpose |
|---------|---------|
| CloudWatch | Query usage metrics |
| Pricing | Fetch model pricing |
| STS | Validate credentials (GetCallerIdentity) |

---

## Implementation Phases

### Phase 1: Foundation (Domain + Infrastructure Core)

1. Add AWS SDK dependency
2. Create `BedrockModel`, `BedrockModelUsage`, `BedrockUsageSummary` domain models
3. Create `BedrockSettingsRepository` protocol and implementation
4. Implement basic `BedrockUsageProbe` with CloudWatch queries
5. Write unit tests for domain models and parsing

### Phase 2: Pricing System

1. Implement `BedrockPricingService` with caching
2. Add bundled default pricing data
3. Implement AWS Pricing API integration
4. Write tests for pricing calculation and caching

### Phase 3: Provider Integration

1. Create `BedrockProvider` class
2. Register provider in `ClaudeBarApp.init()`
3. Add provider icon to Assets
4. Test basic refresh flow

### Phase 4: UI Implementation

1. Add Bedrock to provider pills
2. Create `CostStatCard` variant for budget display
3. Create `BedrockDetailView` for model breakdown
4. Add Bedrock settings section to `SettingsView`

### Phase 5: Polish & Testing

1. Error handling and edge cases
2. Alert integration testing
3. Documentation updates
4. Manual testing on various AWS configurations

---

## Open Questions

1. **AWS SDK bundle size** - Need to verify the SDK doesn't bloat the app significantly
2. **Rate limiting** - CloudWatch has API limits; may need request batching
3. **Cross-region pricing** - Verify pricing is consistent across regions or if we need region-specific lookups

---

## Appendix A: AWS SDK for Swift Usage Patterns

### Package Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
],
targets: [
    .target(
        name: "Infrastructure",
        dependencies: [
            "Domain",
            .product(name: "AWSCloudWatch", package: "aws-sdk-swift"),
            .product(name: "AWSPricing", package: "aws-sdk-swift"),
            .product(name: "AWSSTS", package: "aws-sdk-swift"),
        ]
    ),
]
```

### Client Initialization Patterns

```swift
import AWSCloudWatch
import AWSSTS
import AWSPricing

// Simple initialization with region
let cloudWatchClient = try await CloudWatchClient(region: "us-east-1")

// With custom configuration
let config = try await CloudWatchClient.Config(region: "us-east-1")
let cloudWatchClient = CloudWatchClient(config: config)

// Auto-detect region (uses default credential chain)
let stsClient = try await STSClient()
```

### CloudWatch GetMetricStatistics Example

```swift
func fetchBedrockMetrics(
    client: CloudWatchClient,
    startTime: Date,
    endTime: Date
) async throws -> [MetricDataResult] {

    let input = GetMetricStatisticsInput(
        namespace: "AWS/Bedrock",
        metricName: "InputTokenCount",
        startTime: startTime,
        endTime: endTime,
        period: 86400,  // Daily
        statistics: [.sum],
        dimensions: [
            Dimension(name: "ModelId", value: "anthropic.claude-opus-4-5-20251101-v1:0")
        ]
    )

    let output = try await client.getMetricStatistics(input: input)
    return output.datapoints ?? []
}
```

### STS GetCallerIdentity (Credential Validation)

```swift
func validateCredentials() async throws -> String {
    let stsClient = try await STSClient()
    let input = GetCallerIdentityInput()
    let output = try await stsClient.getCallerIdentity(input: input)

    guard let account = output.account else {
        throw ProbeError.awsCredentialsNotFound
    }
    return account
}
```

### CloudWatch ListMetrics (Discover Active Models)

```swift
func discoverActiveModels(client: CloudWatchClient) async throws -> [String] {
    let input = ListMetricsInput(
        namespace: "AWS/Bedrock",
        metricName: "Invocations"
    )

    let output = try await client.listMetrics(input: input)

    // Extract unique ModelIds from dimensions
    let modelIds = (output.metrics ?? []).compactMap { metric in
        metric.dimensions?.first { $0.name == "ModelId" }?.value
    }

    return Array(Set(modelIds))
}
```

### Error Handling

```swift
do {
    let output = try await client.getMetricStatistics(input: input)
} catch let error as AWSClientRuntime.UnknownAWSHTTPServiceError {
    // Handle AWS-specific errors
    switch error.typeName {
    case "AccessDeniedException":
        throw ProbeError.awsAccessDenied
    case "InvalidParameterValueException":
        throw ProbeError.executionFailed("Invalid CloudWatch parameters")
    default:
        throw ProbeError.executionFailed(error.localizedDescription)
    }
} catch {
    throw ProbeError.executionFailed(error.localizedDescription)
}
```

---

## Appendix B: Model ID Parsing

### Extracting Provider and Model Name

```swift
extension BedrockModel {
    /// Parses a raw AWS model ID into components
    static func parse(modelId: String) -> (provider: String, name: String)? {
        // Format: "provider.model-name-version" or "region.provider.model-name-version"
        let components = modelId.split(separator: ".")

        guard components.count >= 2 else { return nil }

        // Handle region prefix (e.g., "us.anthropic.claude-...")
        let providerIndex = components[0].allSatisfy { $0.isLetter && $0.isLowercase }
            && components[0].count <= 3 ? 1 : 0

        let provider = String(components[providerIndex]).capitalized
        let modelPart = components.dropFirst(providerIndex + 1).joined(separator: ".")

        // Convert model part to friendly name
        let friendlyName = modelPart
            .replacingOccurrences(of: "-v1:0", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")

        return (provider, friendlyName)
    }
}
```

### Known Model Mappings

Override table for models where auto-parsing doesn't produce good names:

```swift
let modelDisplayNames: [String: String] = [
    "anthropic.claude-3-opus-20240229-v1:0": "Claude 3 Opus",
    "anthropic.claude-3-sonnet-20240229-v1:0": "Claude 3 Sonnet",
    "anthropic.claude-3-haiku-20240307-v1:0": "Claude 3 Haiku",
    "anthropic.claude-opus-4-5-20251101-v1:0": "Claude Opus 4.5",
    "anthropic.claude-sonnet-4-5-20250929-v1:0": "Claude Sonnet 4.5",
    "anthropic.claude-haiku-4-5-20251001-v1:0": "Claude Haiku 4.5",
    "mistral.mistral-large-3-675b-instruct": "Mistral Large 3",
    "amazon.nova-pro-v1:0": "Amazon Nova Pro",
    // ... more mappings
]
```
