import Foundation
import Observation

/// Z.ai (GLM Coding Plan) provider - a rich domain model.
/// Z.ai provides an API-compatible replacement for Anthropic's API,
/// offering GLM-4.7 models with generous usage quotas.
@Observable
public final class ZaiProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "zai"
    public let name: String = "Z.ai"
    public let cliCommand: String = "claude"

    public var dashboardURL: URL? {
        URL(string: "https://z.ai/subscribe")
    }

    public var statusPageURL: URL? {
        URL(string: "https://docs.z.ai/devpack/faq")
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
    private let settingsRepository: any ProviderSettingsRepository

    // MARK: - Initialization

    /// Creates a Z.ai provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "zai")
    }

    // MARK: - AIProvider Protocol

    /// Checks if the provider is available
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
}
