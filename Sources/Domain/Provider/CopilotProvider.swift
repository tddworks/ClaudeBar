import Foundation
import Observation

/// GitHub Copilot AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
@Observable
public final class CopilotProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "copilot"
    public let name: String = "Copilot"
    public let cliCommand: String = "gh"

    public var dashboardURL: URL? {
        URL(string: "https://github.com/settings/billing/summary")
    }

    public var statusPageURL: URL? {
        URL(string: "https://www.githubstatus.com")
    }

    /// UserDefaults key for persisting isEnabled state
    private static let isEnabledKey = "provider.copilot.isEnabled"

    /// Whether the provider is enabled (persisted to UserDefaults, defaults to false - requires setup)
    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
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

    // MARK: - Initialization

    /// Creates a Copilot provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    public init(probe: any UsageProbe) {
        self.probe = probe
        // Load persisted enabled state (defaults to false - requires setup)
        self.isEnabled = UserDefaults.standard.object(forKey: Self.isEnabledKey) as? Bool ?? false
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
}
