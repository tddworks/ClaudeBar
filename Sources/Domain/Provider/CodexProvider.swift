import Foundation
import Observation

/// Codex AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: RPC (default) and API.
@Observable
public final class CodexProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity

    public let id: String = "codex"
    public let name: String = "Codex"
    public let cliCommand: String = "codex"

    public var dashboardURL: URL? {
        URL(string: "https://platform.openai.com/usage")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.openai.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Probe Mode

    /// The current probe mode (RPC or API)
    public var probeMode: CodexProbeMode {
        get {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                return codexSettings.codexProbeMode()
            }
            return .rpc
        }
        set {
            if let codexSettings = settingsRepository as? CodexSettingsRepository {
                codexSettings.setCodexProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The RPC probe for fetching usage data via `codex app-server`
    private let rpcProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .rpc:
            return rpcProbe
        case .api:
            // Fall back to RPC if API probe not available
            return apiProbe ?? rpcProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Codex provider with RPC probe only (legacy initializer)
    /// - Parameters:
    ///   - probe: The RPC probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.rpcProbe = probe
        self.apiProbe = nil
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "codex")
    }

    /// Creates a Codex provider with both RPC and API probes
    /// - Parameters:
    ///   - rpcProbe: The RPC probe for fetching usage via `codex app-server`
    ///   - apiProbe: The API probe for fetching usage via HTTP API
    ///   - settingsRepository: The repository for persisting settings (must be CodexSettingsRepository for mode switching)
    public init(
        rpcProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        settingsRepository: any CodexSettingsRepository
    ) {
        self.rpcProbe = rpcProbe
        self.apiProbe = apiProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "codex")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

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
