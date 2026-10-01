import Foundation
import Observation

/// Command Code — monitors 5-hour, weekly, and monthly-credit quotas via the
/// same HTTP APIs the `cmd` CLI's `/usage` command uses.
@MainActor
@Observable
public final class CommandCodeProvider: AIProvider {
    // MARK: - Identity

    public let id: String = "commandcode"
    public let name: String = "Command Code"
    public let cliCommand: String = "cmd"

    public var dashboardURL: URL? {
        URL(string: "https://commandcode.ai/usage")
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
        self.isEnabled = settingsRepository.isEnabled(forProvider: "commandcode")
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
