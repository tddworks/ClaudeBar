import Foundation
import Observation

/// Antigravity AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
@Observable
public final class AntigravityProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "antigravity"
    public let name: String = "Antigravity"
    public let cliCommand: String = "antigravity"

    public var dashboardURL: URL? {
        nil  // Antigravity is local-only, no dashboard
    }

    public var statusPageURL: URL? {
        nil  // No external status page
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

    /// Creates an Antigravity provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    public init(probe: any UsageProbe) {
        self.probe = probe
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
