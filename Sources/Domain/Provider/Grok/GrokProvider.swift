import Foundation
import Observation

/// Grok Build (xAI) — monitors weekly credit usage and per-product limits
/// (Grok Build, Grok Imagine, Grok Voice) via the xAI billing API.
@MainActor
@Observable
public final class GrokProvider: AIProvider {
    // MARK: - Identity

    public let id: String = "grok"
    public let name: String = "Grok"
    public let cliCommand: String = "grok"

    public var dashboardURL: URL? {
        URL(string: "https://grok.com/?_s=usage")
    }

    public var statusPageURL: URL? {
        URL(string: "https://status.x.ai")
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
        self.isEnabled = settingsRepository.isEnabled(forProvider: "grok")
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
