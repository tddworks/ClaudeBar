import Foundation
import Observation

/// OpenCode Go — monitors rolling (5h), weekly, and monthly usage via the
/// opencode.ai usage API, falling back to the local opencode DB when no API key is configured.
@MainActor
@Observable
public final class OpenCodeProvider: AIProvider {
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
