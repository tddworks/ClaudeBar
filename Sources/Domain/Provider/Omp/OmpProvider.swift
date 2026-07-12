import Foundation
import Observation

/// Oh My Pi — coding-agent harness that pools OAuth accounts across upstream
/// providers (Anthropic, OpenAI Codex, Z.ai, ...). Monitors the rate-limit
/// windows of every authenticated account via `omp usage --json`.
@MainActor
@Observable
public final class OmpProvider: AIProvider {
    // MARK: - Identity

    public let id: String = "omp"
    public let name: String = "Oh My Pi"
    public let cliCommand: String = "omp"

    public var dashboardURL: URL? {
        URL(string: "https://omp.sh")
    }

    public var statusPageURL: URL? {
        nil
    }

    /// `omp usage` caches upstream reports itself, and each probe spawns the
    /// Bun-based CLI — don't let a fast user-chosen interval respawn it every
    /// minute in the background for unchanged data. Interactive refreshes are
    /// unaffected (see issue #204 rationale on `AIProvider`).
    public var backgroundRefreshFloor: Duration? { .seconds(300) }

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
        self.isEnabled = settingsRepository.isEnabled(forProvider: "omp")
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
