import Foundation
import Observation

/// Kimi AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: CLI (default) and API.
@MainActor
@Observable
public final class KimiProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "kimi"
    public let name: String = "Kimi"
    public let cliCommand: String = "kimi"

    public var dashboardURL: URL? {
        URL(string: "https://www.kimi.com/code/console")
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

    // MARK: - Probe Mode

    /// The current probe mode (CLI or API)
    public var probeMode: KimiProbeMode {
        get {
            if let kimiSettings = settingsRepository as? KimiSettingsRepository {
                return kimiSettings.kimiProbeMode()
            }
            return .cli
        }
        set {
            if let kimiSettings = settingsRepository as? KimiSettingsRepository {
                kimiSettings.setKimiProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The CLI probe for fetching usage data via interactive `kimi` CLI
    private let cliProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .cli:
            return cliProbe
        case .api:
            // Fall back to CLI if API probe not available
            return apiProbe ?? cliProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Kimi provider with a single probe (legacy initializer)
    /// - Parameters:
    ///   - probe: The probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.cliProbe = probe
        self.apiProbe = nil
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "kimi")
    }

    /// Creates a Kimi provider with both CLI and API probes
    /// - Parameters:
    ///   - cliProbe: The CLI probe for fetching usage via interactive `kimi` CLI
    ///   - apiProbe: The API probe for fetching usage via HTTP API
    ///   - settingsRepository: The repository for persisting settings (must be KimiSettingsRepository for mode switching)
    public init(
        cliProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        settingsRepository: any KimiSettingsRepository
    ) {
        self.cliProbe = cliProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "kimi")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Uses the active probe based on current probe mode.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await activeProbe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }

    /// Whether API mode is available (API probe was provided)
    public var supportsApiMode: Bool {
        apiProbe != nil
    }
}
