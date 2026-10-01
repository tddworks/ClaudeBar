import Foundation
import Observation

/// AmpCode AI provider (by Sourcegraph).
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
@MainActor
@Observable
public final class AmpCodeProvider: AIProvider {

    // MARK: - Identity

    public let id: String = "ampcode"
    public let name: String = "Amp"
    public let cliCommand: String = "amp"

    public var dashboardURL: URL? {
        URL(string: "https://ampcode.com/settings")
    }

    public var statusPageURL: URL? {
        nil
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

    /// Creates an AmpCode provider with the specified probe.
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Load initial enabled state
        self.isEnabled = settingsRepository.isEnabled(forProvider: "ampcode")
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
