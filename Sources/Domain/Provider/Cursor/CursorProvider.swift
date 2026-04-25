import Foundation
import Combine

/// Cursor AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
public final class CursorProvider: ObservableObject, AIProvider, @unchecked Sendable {
    public let objectWillChange = ObservableObjectPublisher()

    // MARK: - Identity (Protocol Requirement)

    public let id: String = "cursor"
    public let name: String = "Cursor"
    public let cliCommand: String = "cursor"

    public var dashboardURL: URL? {
        URL(string: "https://www.cursor.com/settings")
    }

    public var statusPageURL: URL? {
        nil
    }

    /// Whether the provider is enabled (persisted via settingsRepository)
    @Published public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    @Published public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable)
    @Published public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh
    @Published public private(set) var lastError: Error?

    // MARK: - Internal

    /// The probe for fetching usage data via Cursor's API
    private let probe: any UsageProbe

    /// The settings repository for persisting provider settings
    private let settingsRepository: any ProviderSettingsRepository

    // MARK: - Initialization

    /// Creates a Cursor provider
    /// - Parameters:
    ///   - probe: The probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "cursor")
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
