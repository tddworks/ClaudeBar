import Foundation
import Combine

/// Alibaba Coding Plan AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
public final class AlibabaProvider: ObservableObject, AIProvider, @unchecked Sendable {
    public let objectWillChange = ObservableObjectPublisher()

    // MARK: - Identity

    public let id: String = "alibaba"
    public let name: String = "Alibaba"
    public let cliCommand: String = "alibaba-coding-plan"

    public var dashboardURL: URL? {
        URL(string: "https://modelstudio.console.alibabacloud.com")
    }

    public var statusPageURL: URL? { nil }

    /// Whether the provider is enabled (persisted via settingsRepository)
    @Published public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var lastError: Error?

    // MARK: - Internal

    private let probe: any UsageProbe
    private let settingsRepository: any AlibabaSettingsRepository

    // MARK: - Initialization

    public init(probe: any UsageProbe, settingsRepository: any AlibabaSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        // Default to disabled - opt-in provider (requires cookie/API key setup)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "alibaba", defaultValue: false)
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

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
