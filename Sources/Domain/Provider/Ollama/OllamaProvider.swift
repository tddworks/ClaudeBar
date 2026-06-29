import Foundation
import Observation

/// Ollama AI provider - a rich domain model.
///
/// Tracks usage for Ollama Pro / Ollama Cloud (the paid subscription at
/// ollama.com — distinct from the open-source local-only Ollama runtime).
/// Observable class with its own state (isSyncing, snapshot, error).
///
/// Supports dual probe modes: `api` (Bearer token, default) and `web`
/// (browser session cookie). The active mode is persisted via
/// `OllamaSettingsRepository`.
@Observable
public final class OllamaProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "ollama"
    public let name: String = "Ollama"
    public let cliCommand: String = "ollama"

    public var dashboardURL: URL? {
        URL(string: "https://ollama.com/settings")
    }

    public var statusPageURL: URL? {
        nil
    }

    /// Whether the provider is enabled (persisted via settingsRepository).
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data.
    public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable).
    public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh.
    public private(set) var lastError: Error?

    // MARK: - Probe Mode

    /// The current probe mode (API or Web).
    public var probeMode: OllamaProbeMode {
        get {
            if let ollamaSettings = settingsRepository as? OllamaSettingsRepository {
                return ollamaSettings.ollamaProbeMode()
            }
            return .api
        }
        set {
            if let ollamaSettings = settingsRepository as? OllamaSettingsRepository {
                ollamaSettings.setOllamaProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The API probe (Bearer token to ollama.com API).
    private let apiProbe: any UsageProbe

    /// The Web probe (session-cookie scraping of ollama.com/settings).
    /// Optional so the provider works in environments where cookie reading
    /// is unsupported.
    private let webProbe: (any UsageProbe)?

    /// The settings repository for persisting provider settings.
    private let settingsRepository: any ProviderSettingsRepository

    /// Returns the probe matching the current mode, falling back to the
    /// other probe when the requested one is unavailable.
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .api:
            return apiProbe
        case .web:
            return webProbe ?? apiProbe
        }
    }

    // MARK: - Initialization

    /// Creates an Ollama provider with a single API probe (no web fallback).
    /// - Parameters:
    ///   - probe: The probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.apiProbe = probe
        self.webProbe = nil
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(
            forProvider: "ollama",
            defaultValue: false
        )
    }

    /// Creates an Ollama provider with both API and Web probes.
    /// - Parameters:
    ///   - apiProbe: The probe for fetching usage via the Ollama HTTP API (Bearer token)
    ///   - webProbe: The probe for fetching usage via the ollama.com/settings HTML scrape
    ///   - settingsRepository: The repository for persisting settings (must be an
    ///     `OllamaSettingsRepository` for mode switching to persist)
    public init(
        apiProbe: any UsageProbe,
        webProbe: any UsageProbe,
        settingsRepository: any OllamaSettingsRepository
    ) {
        self.apiProbe = apiProbe
        self.webProbe = webProbe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(
            forProvider: "ollama",
            defaultValue: false
        )
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await activeProbe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Uses the active probe based on the current probe mode.
    /// Sets `isSyncing` during refresh and captures any errors.
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

    /// Whether Web mode is available (a web probe was provided).
    public var supportsWebMode: Bool {
        webProbe != nil
    }
}
