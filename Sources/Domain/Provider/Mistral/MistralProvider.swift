import Foundation
import Observation

/// Mistral AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: Local Logs (default) and Code API.
@Observable
public final class MistralProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "mistral"
    public let name: String = "Mistral"
    public let cliCommand: String = "" // log-only provider, no CLI

    public var dashboardURL: URL? {
        URL(string: "https://console.mistral.ai/codestral/cli")
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

    /// The current probe mode (Local Logs or Vibe API)
    public var probeMode: MistralProbeMode {
        get {
            if let mistralSettings = settingsRepository as? MistralSettingsRepository {
                return mistralSettings.mistralProbeMode()
            }
            return .localLogs
        }
        set {
            if let mistralSettings = settingsRepository as? MistralSettingsRepository {
                mistralSettings.setMistralProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The local logs probe (reads ~/.vibe/logs/session/)
    private let localLogsProbe: any UsageProbe

    /// The API probe for fetching usage via Mistral Console tRPC API
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .localLogs:
            return localLogsProbe
        case .api:
            return apiProbe ?? localLogsProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Mistral provider with a single probe (legacy initializer)
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.localLogsProbe = probe
        self.apiProbe = nil
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "mistral", defaultValue: false)
    }

    /// Creates a Mistral provider with both local logs and API probes
    public init(
        localLogsProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        settingsRepository: any MistralSettingsRepository
    ) {
        self.localLogsProbe = localLogsProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "mistral", defaultValue: false)
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Uses the active probe based on current probe mode.
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
