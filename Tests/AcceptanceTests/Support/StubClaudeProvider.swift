import Foundation
import Observation
@testable import Domain

/// "Another provider" for tests about the monitor, the lineup and selection —
/// Claude's identity fed by a stubbed probe. Claude itself is now a definition
/// (`Modules/Providers/Resources/Providers/claude.json`), tested end to end in
/// `ProvidersTests`; these tests only need something with its id and name.
@MainActor
@Observable
final class StubClaudeProvider: AIProvider {
    let id = "claude"
    let name = "Claude"
    let cliCommand = "claude"
    var dashboardURL: URL? { URL(string: "https://console.anthropic.com/settings/billing") }
    var statusPageURL: URL? { URL(string: "https://status.anthropic.com") }

    var isEnabled: Bool {
        didSet { settingsRepository.setEnabled(isEnabled, forProvider: id) }
    }

    private(set) var isSyncing = false
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: Error?

    /// The background floor a data source with a cache imposes — Claude's
    /// API sets 15 minutes (pinned against `claude.json` in ProvidersTests).
    let backgroundRefreshFloor: Duration?

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository, backgroundRefreshFloor: Duration? = nil) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.backgroundRefreshFloor = backgroundRefreshFloor
        self.isEnabled = settingsRepository.isEnabled(forProvider: "claude")
    }

    func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    @discardableResult
    func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let usage = try await probe.probe()
            snapshot = usage
            lastError = nil
            return usage
        } catch {
            lastError = error
            throw error
        }
    }
}
