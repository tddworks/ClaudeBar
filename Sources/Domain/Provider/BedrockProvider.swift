import Foundation
import Observation

/// AWS Bedrock AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Monitors Bedrock usage via CloudWatch metrics and calculates costs.
@Observable
public final class BedrockProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "bedrock"
    public let name: String = "AWS Bedrock"
    public let cliCommand: String = "aws" // AWS CLI, but we use SDK

    public var dashboardURL: URL? {
        URL(string: "https://console.aws.amazon.com/bedrock/home")
    }

    public var statusPageURL: URL? {
        URL(string: "https://health.aws.amazon.com/health/status")
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable)
    public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh
    public private(set) var lastError: Error?

    // MARK: - Internal

    /// The probe used to fetch usage data
    private let probe: any UsageProbe
    private let settingsRepository: any BedrockSettingsRepository

    // MARK: - Initialization

    /// Creates a Bedrock provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any BedrockSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Default to disabled - user must configure AWS profile first
        self.isEnabled = settingsRepository.isEnabled(forProvider: "bedrock", defaultValue: false)
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - Bedrock-Specific Accessors

    /// The Bedrock usage summary from the current snapshot
    public var bedrockUsage: BedrockUsageSummary? {
        snapshot?.bedrockUsage
    }

    /// Formatted total cost for today
    public var formattedTodayCost: String? {
        bedrockUsage?.formattedTotalCost
    }

    /// Models sorted by cost (highest first)
    public var modelsBySpend: [BedrockModelUsage] {
        bedrockUsage?.modelsBySpend ?? []
    }
}
