import Foundation
import Observation

/// GitHub Copilot AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Supports dual probe modes: Billing API (default) and Copilot Internal API.
/// Owns its probe, credentials, and manages its own data lifecycle.
@MainActor
@Observable
public final class CopilotProvider: AIProvider {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "copilot"
    public let name: String = "Copilot"
    public let cliCommand: String = "gh"

    public var dashboardURL: URL? {
        URL(string: "https://github.com/settings/copilot/features")
    }

    public var statusPageURL: URL? {
        URL(string: "https://www.githubstatus.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository, defaults to false - requires setup)
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

    // MARK: - Credentials (Observable)

    /// The GitHub username for API calls
    public var username: String {
        didSet {
            settingsRepository.saveGithubUsername(username)
        }
    }

    /// Whether a GitHub token is configured
    public var hasToken: Bool {
        settingsRepository.hasGithubToken()
    }

    // MARK: - Probe Mode

    /// The current probe mode (billing or copilotAPI)
    public var probeMode: CopilotProbeMode {
        get {
            settingsRepository.copilotProbeMode()
        }
        set {
            settingsRepository.setCopilotProbeMode(newValue)
        }
    }

    // MARK: - Internal

    /// The billing probe for fetching usage data via GitHub Billing API
    private let billingProbe: any UsageProbe

    /// The internal API probe for fetching usage data via Copilot Internal API (optional)
    private let internalProbe: (any UsageProbe)?

    private let settingsRepository: any CopilotSettingsRepository

    /// Returns the active probe based on current mode
    private var activeProbe: any UsageProbe {
        switch probeMode {
        case .billing:
            return billingProbe
        case .copilotAPI:
            // Fall back to billing if internal probe not available
            return internalProbe ?? billingProbe
        }
    }

    // MARK: - Initialization

    /// Creates a Copilot provider with a single probe (legacy initializer for tests)
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting Copilot settings and credentials
    public init(
        probe: any UsageProbe,
        settingsRepository: any CopilotSettingsRepository
    ) {
        self.billingProbe = probe
        self.internalProbe = nil
        self.settingsRepository = settingsRepository
        // Copilot defaults to false (requires setup)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "copilot", defaultValue: false)
        // Load persisted username
        self.username = settingsRepository.getGithubUsername() ?? ""
    }

    /// Creates a Copilot provider with both billing and internal API probes
    /// - Parameters:
    ///   - billingProbe: The probe for fetching usage via GitHub Billing API
    ///   - internalProbe: The probe for fetching usage via Copilot Internal API
    ///   - settingsRepository: The repository for persisting settings (must be CopilotSettingsRepository for mode switching)
    public init(
        billingProbe: any UsageProbe,
        internalProbe: any UsageProbe,
        settingsRepository: any CopilotSettingsRepository
    ) {
        self.billingProbe = billingProbe
        self.internalProbe = internalProbe
        self.settingsRepository = settingsRepository
        // Copilot defaults to false (requires setup)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "copilot", defaultValue: false)
        // Load persisted username
        self.username = settingsRepository.getGithubUsername() ?? ""
    }

    // MARK: - Credential Management

    /// Saves the GitHub token
    public func saveToken(_ token: String) {
        settingsRepository.saveGithubToken(token)
    }

    /// Retrieves the GitHub token
    public func getToken() -> String? {
        settingsRepository.getGithubToken()
    }

    /// Deletes the GitHub token and username
    public func deleteCredentials() {
        settingsRepository.deleteGithubToken()
        settingsRepository.deleteGithubUsername()
        username = ""
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

    /// Whether Copilot Internal API mode is available (internal probe was provided)
    public var supportsInternalApiMode: Bool {
        internalProbe != nil
    }
}
