import Foundation
import Observation
@testable import Domain

/// "Another provider" for tests about the monitor, the lineup and selection —
/// Codex's identity fed by a stubbed probe. Codex itself is now a definition
/// (`Modules/Providers/Resources/Providers/codex.json`), tested end to end in
/// `ProvidersTests`; these tests only need something with its id and name.
@MainActor
@Observable
final class StubCodexProvider: AIProvider {
    let id = "codex"
    let name = "Codex"
    let cliCommand = "codex"
    var dashboardURL: URL? { URL(string: "https://platform.openai.com/usage") }
    var statusPageURL: URL? { URL(string: "https://status.openai.com") }

    var isEnabled: Bool {
        didSet { settingsRepository.setEnabled(isEnabled, forProvider: id) }
    }

    private(set) var isSyncing = false
    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: Error?

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "codex")
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
