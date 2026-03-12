import Foundation
import Observation

/// Claude AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: CLI (default) and API.
@Observable
public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "claude"
    public let name: String = "Claude"
    public let cliCommand: String = "claude"

    public var dashboardURL: URL? {
        URL(string: "https://console.anthropic.com/settings/billing")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.anthropic.com")
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

    /// The current guest pass information (nil if never fetched)
    public private(set) var guestPass: ClaudePass?

    /// Whether the provider is currently fetching passes
    public private(set) var isFetchingPasses: Bool = false

    // MARK: - Probe Mode

    /// The current probe mode (CLI or API)
    public var probeMode: ClaudeProbeMode {
        get {
            // Only use ClaudeSettingsRepository if available
            if let claudeSettings = settingsRepository as? ClaudeSettingsRepository {
                return claudeSettings.claudeProbeMode()
            }
            return .cli
        }
        set {
            if let claudeSettings = settingsRepository as? ClaudeSettingsRepository {
                claudeSettings.setClaudeProbeMode(newValue)
            }
        }
    }

    // MARK: - Internal

    /// The CLI probe for fetching usage data via `claude /usage`
    private let cliProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The probe used to fetch guest pass data
    private let passProbe: (any ClaudePassProbing)?

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    /// Optional analyzer for daily usage from JSONL session data
    private let dailyUsageAnalyzer: (any DailyUsageAnalyzing)?

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

    /// Creates a Claude provider with CLI probe only (legacy initializer)
    /// - Parameters:
    ///   - probe: The CLI probe to use for fetching usage data
    ///   - passProbe: The probe to use for fetching guest pass data (optional)
    ///   - settingsRepository: The repository for persisting settings
    public init(
        probe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ProviderSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        self.cliProbe = probe
        self.apiProbe = nil
        self.passProbe = passProbe
        self.settingsRepository = settingsRepository
        self.dailyUsageAnalyzer = dailyUsageAnalyzer
        // Load persisted enabled state (defaults to true)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    /// Creates a Claude provider with both CLI and API probes
    /// - Parameters:
    ///   - cliProbe: The CLI probe for fetching usage via `claude /usage`
    ///   - apiProbe: The API probe for fetching usage via HTTP API
    ///   - passProbe: The probe to use for fetching guest pass data (optional)
    ///   - settingsRepository: The repository for persisting settings (must be ClaudeSettingsRepository for mode switching)
    public init(
        cliProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ClaudeSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        self.cliProbe = cliProbe
        self.apiProbe = apiProbe
        self.passProbe = passProbe
        self.settingsRepository = settingsRepository
        self.dailyUsageAnalyzer = dailyUsageAnalyzer
        // Load persisted enabled state (defaults to true)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        switch probeMode {
        case .cli:
            if await cliProbe.isAvailable() {
                return true
            }
            if let apiProbe, await apiProbe.isAvailable() {
                return true
            }
            return false
        case .api:
            if let apiProbe, await apiProbe.isAvailable() {
                return true
            }
            return await cliProbe.isAvailable()
        }
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Uses the active probe based on current probe mode.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await primaryProbe().probe()
            snapshot = await attachDailyReport(to: newSnapshot)
            lastError = nil
            return snapshot!
        } catch {
            if let fallback = await fallbackProbe() {
                do {
                    let newSnapshot = try await fallback.probe()
                    snapshot = await attachDailyReport(to: newSnapshot)
                    lastError = nil
                    return snapshot!
                } catch {
                    lastError = error
                    throw error
                }
            }

            lastError = error
            throw error
        }
    }

    /// Attaches daily usage report to snapshot if analyzer is available.
    private func attachDailyReport(to snapshot: UsageSnapshot) async -> UsageSnapshot {
        guard let analyzer = dailyUsageAnalyzer,
              let report = try? await analyzer.analyzeToday(),
              !report.today.isEmpty || !report.previous.isEmpty else {
            return snapshot
        }
        return UsageSnapshot(
            providerId: snapshot.providerId,
            quotas: snapshot.quotas,
            capturedAt: snapshot.capturedAt,
            accountEmail: snapshot.accountEmail,
            accountOrganization: snapshot.accountOrganization,
            loginMethod: snapshot.loginMethod,
            accountTier: snapshot.accountTier,
            costUsage: snapshot.costUsage,
            bedrockUsage: snapshot.bedrockUsage,
            dailyUsageReport: report
        )
    }

    private func primaryProbe() -> any UsageProbe {
        switch probeMode {
        case .cli:
            return cliProbe
        case .api:
            return apiProbe ?? cliProbe
        }
    }

    private func fallbackProbe() async -> (any UsageProbe)? {
        switch probeMode {
        case .cli:
            guard let apiProbe, await apiProbe.isAvailable() else {
                return nil
            }
            return apiProbe
        case .api:
            return await cliProbe.isAvailable() ? cliProbe : nil
        }
    }

    // MARK: - Guest Pass

    /// Fetches the current guest pass information.
    /// Sets isFetchingPasses during fetch and captures any errors.
    @discardableResult
    public func fetchPasses() async throws -> ClaudePass {
        guard let passProbe else {
            throw PassError.probeNotConfigured
        }

        isFetchingPasses = true
        defer { isFetchingPasses = false }

        do {
            let pass = try await passProbe.probe()
            guestPass = pass
            lastError = nil
            return pass
        } catch {
            lastError = error
            throw error
        }
    }

    /// Whether guest passes feature is available
    public var supportsGuestPasses: Bool {
        passProbe != nil
    }

    /// Whether API mode is available (API probe was provided)
    public var supportsApiMode: Bool {
        apiProbe != nil
    }
}

// MARK: - Pass Error

public enum PassError: Error, LocalizedError {
    case probeNotConfigured

    public var errorDescription: String? {
        switch self {
        case .probeNotConfigured:
            return "Guest pass probe is not configured"
        }
    }
}
