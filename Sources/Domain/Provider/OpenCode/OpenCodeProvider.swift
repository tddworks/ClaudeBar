import Foundation
import Observation

/// OpenCode Go — monitors 5h ($12), weekly ($30), monthly ($60) usage from local opencode DB.
@Observable
public final class OpenCodeProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity

    public let id: String = "opencode-go"
    public let name: String = "OpenCode Go"
    public let cliCommand: String = "opencode"

    public var dashboardURL: URL? {
        URL(string: "https://opencode.ai/auth")
    }

    public var statusPageURL: URL? {
        nil
    }

    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    // MARK: - Internal

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "opencode-go")
    }

    // MARK: - AIProvider

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
