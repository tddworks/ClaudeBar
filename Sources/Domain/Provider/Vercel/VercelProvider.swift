import Foundation
import Observation

/// Vercel AI Gateway provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe and manages its own data lifecycle.
/// Displays the team's AI Gateway credits balance (dollar-based).
@MainActor
@Observable
public final class VercelProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "vercel-gateway"
    public let name: String = "Vercel Gateway"
    public let cliCommand: String = "" // API-only provider, no CLI (纯 API 提供者，无 CLI)

    public var dashboardURL: URL? {
        URL(string: "https://vercel.com/dashboard/ai-gateway")
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
    private let settingsRepository: any VercelSettingsRepository

    // MARK: - Initialization

    /// Creates a Vercel provider with the specified probe
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any VercelSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Default to disabled - requires API key configuration
        self.isEnabled = settingsRepository.isEnabled(forProvider: "vercel-gateway", defaultValue: false)
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        guard !isSyncing else {
            throw ProbeError.executionFailed("Vercel refresh already in progress")
        }

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
