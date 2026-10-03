import Foundation
import Observation

/// Claude AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: CLI (default) and API.
@MainActor
@Observable
public final class ClaudeProvider: AIProvider {
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

    /// The last error from a guest pass fetch (nil when the last fetch succeeded).
    /// Kept separate from `lastError` so a failed invitation-link fetch never
    /// makes the provider's usage data look unavailable.
    public private(set) var passError: Error?

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

    /// Background poll cadence floor. In API mode, background refreshes are
    /// floored at 15 min to match `ClaudeAPIUsageProbe`'s snapshot-cache TTL:
    /// polling faster only re-serves the cache (or, once expired, risks 429s),
    /// so there's no benefit to a tighter background cadence (issue #204). CLI
    /// mode keeps the user's chosen interval (no floor), and so does Local
    /// File mode — reading buddy-tokens.json is a cheap local file read.
    public var backgroundRefreshFloor: Duration? {
        switch probeMode {
        case .api: return .seconds(900)
        case .cli, .localFile: return nil
        }
    }

    // MARK: - Internal

    /// The CLI probe for fetching usage data via `claude /usage`
    private let cliProbe: any UsageProbe

    /// The API probe for fetching usage data via HTTP API (optional)
    private let apiProbe: (any UsageProbe)?

    /// The Local File probe for fetching Claude Desktop's daily token count
    /// from buddy-tokens.json (optional, issue #198)
    private let fileProbe: (any UsageProbe)?

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
        case .localFile:
            // Fall back to CLI if the file probe was never injected (legacy
            // initializer) so the provider stays functional.
            return fileProbe ?? cliProbe
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
        self.fileProbe = nil
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
    ///   - fileProbe: The Local File probe for fetching Claude Desktop's daily
    ///     token count from buddy-tokens.json (optional, issue #198)
    ///   - passProbe: The probe to use for fetching guest pass data (optional)
    ///   - settingsRepository: The repository for persisting settings (must be ClaudeSettingsRepository for mode switching)
    public init(
        cliProbe: any UsageProbe,
        apiProbe: any UsageProbe,
        fileProbe: (any UsageProbe)? = nil,
        passProbe: (any ClaudePassProbing)? = nil,
        settingsRepository: any ClaudeSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil
    ) {
        self.cliProbe = cliProbe
        self.apiProbe = apiProbe
        self.fileProbe = fileProbe
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
            guard cliFallbackEnabled else { return false }
            return await cliProbe.isAvailable()
        case .localFile:
            // File mode answers for the file alone: it exists precisely for
            // users without the CLI, so CLI availability is irrelevant here.
            guard let fileProbe else {
                return await cliProbe.isAvailable()
            }
            return await fileProbe.isAvailable()
        }
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Interactive refresh: delegates to the kind-aware implementation.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Uses the active probe based on current probe mode.
    /// Sets isSyncing during refresh and captures any errors.
    ///
    /// The probe and fallback behaviour are identical for both kinds — CLI stays
    /// CLI, the rate-limit short-circuit still holds. The only difference is that
    /// a `.background` refresh skips the daily-usage JSONL scan
    /// (`attachDailyReport`), which the menu-bar label never shows; that scan
    /// runs only when the dropdown is open, which always refreshes interactively
    /// (issue #204).
    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await primaryProbe().probe()
            snapshot = await report(for: newSnapshot, kind: kind)
            lastError = nil
            return snapshot!
        } catch let primaryError {
            if Self.shouldAttemptFallback(after: primaryError),
               let fallback = await fallbackProbe() {
                do {
                    let newSnapshot = try await fallback.probe()
                    snapshot = await report(for: newSnapshot, kind: kind)
                    lastError = nil
                    return snapshot!
                } catch {
                    // Both probes failed. Surface the primary error — it is
                    // the actual root cause (e.g. HTTP 429). The fallback's
                    // failure is incidental and would otherwise mask it,
                    // sending users chasing the wrong problem.
                    lastError = primaryError
                    throw primaryError
                }
            }

            lastError = primaryError
            throw primaryError
        }
    }

    /// Decides whether the fallback probe should run after the primary fails.
    /// Rate-limit failures are an upstream per-token throttle: the CLI talks
    /// to the same Anthropic backend, so the fallback can't help and would
    /// just amplify the problem. Surface the rate-limit error immediately so
    /// the backoff window does its job. All other failure modes (auth,
    /// parse, network, etc.) still try the fallback — those can legitimately
    /// be recovered by the alternate probe path.
    private static func shouldAttemptFallback(after error: Error) -> Bool {
        if case ProbeError.rateLimited = error { return false }
        return true
    }

    /// Attaches the daily-usage report for interactive refreshes only.
    /// Background refreshes (the menu-bar poll) skip the JSONL scan to stay cheap
    /// — the menu-bar label never renders the daily report, and the dropdown that
    /// does always refreshes interactively (issue #204).
    private func report(for snapshot: UsageSnapshot, kind: RefreshKind) async -> UsageSnapshot {
        switch kind {
        case .interactive:
            return await attachDailyReport(to: snapshot)
        case .background:
            return snapshot
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
        case .localFile:
            return fileProbe ?? cliProbe
        }
    }

    private var cliFallbackEnabled: Bool {
        (settingsRepository as? ClaudeSettingsRepository)?
            .claudeCliFallbackEnabled() ?? true
    }

    private func fallbackProbe() async -> (any UsageProbe)? {
        switch probeMode {
        case .cli:
            guard let apiProbe, await apiProbe.isAvailable() else {
                return nil
            }
            return apiProbe
        case .api:
            guard cliFallbackEnabled else { return nil }
            return await cliProbe.isAvailable() ? cliProbe : nil
        case .localFile:
            // No cross-fallback: the file reports daily token totals while
            // CLI/API report five-hour/weekly windows. Substituting one for
            // the other would present the wrong semantic as if it were the
            // user's chosen data, so a failing file probe surfaces its error
            // (issue #198).
            return nil
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
            passError = nil
            return pass
        } catch {
            passError = error
            throw error
        }
    }

    /// Dismisses the last guest pass error.
    public func clearPassError() {
        passError = nil
    }

    /// Whether the guest passes feature is available.
    /// Requires both a configured probe and a Max account — Anthropic issues
    /// invitation links to Max subscribers only, and an unknown tier is not
    /// evidence of one (issue #243).
    public var supportsGuestPasses: Bool {
        passProbe != nil && snapshot?.accountTier?.supportsGuestPasses == true
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
