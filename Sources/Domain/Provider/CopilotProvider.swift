import Foundation
import Observation

/// GitHub Copilot AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe, credentials, and manages its own data lifecycle.
@Observable
public final class CopilotProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "copilot"
    public let name: String = "Copilot"
    public let cliCommand: String = "gh"

    public var dashboardURL: URL? {
        URL(string: "https://github.com/settings/billing/summary")
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
            credentialRepository.save(username, forKey: CredentialKey.githubUsername)
        }
    }

    /// Whether a GitHub token is configured
    public var hasToken: Bool {
        credentialRepository.exists(forKey: CredentialKey.githubToken)
    }

    // MARK: - Internal

    /// The probe used to fetch usage data
    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository
    private let credentialRepository: any CredentialRepository
    private let configRepository: any ProviderConfigRepository

    // MARK: - Initialization

    /// Creates a Copilot provider with the specified dependencies
    /// - Parameter probe: The probe to use for fetching usage data
    /// - Parameter settingsRepository: The repository for persisting settings
    /// - Parameter credentialRepository: The repository for credentials (token, username)
    /// - Parameter configRepository: The repository for provider-specific configuration
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository,
        credentialRepository: any CredentialRepository,
        configRepository: any ProviderConfigRepository
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.credentialRepository = credentialRepository
        self.configRepository = configRepository
        // Copilot defaults to false (requires setup)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "copilot", defaultValue: false)
        // Load persisted username
        self.username = credentialRepository.get(forKey: CredentialKey.githubUsername) ?? ""
    }

    // MARK: - Credential Management

    /// Saves the GitHub token
    public func saveToken(_ token: String) {
        credentialRepository.save(token, forKey: CredentialKey.githubToken)
    }

    /// Retrieves the GitHub token
    public func getToken() -> String? {
        credentialRepository.get(forKey: CredentialKey.githubToken)
    }

    /// Deletes the GitHub token and username
    public func deleteCredentials() {
        credentialRepository.delete(forKey: CredentialKey.githubToken)
        credentialRepository.delete(forKey: CredentialKey.githubUsername)
        username = ""
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
