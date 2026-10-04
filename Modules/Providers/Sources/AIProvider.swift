import Foundation
import Quotas

/// Distinguishes how much work a refresh should do and whether it counts as
/// explicit user intent.
///
/// - `.interactive`: a genuine click (Refresh button, Touch Bar / notch
///   refresh, `claudebar://refresh`, provider switch). Providers may do their
///   most expensive work and treat success as "the user connected".
/// - `.background`: the periodic menu-bar poll. Must stay cheap — skipping
///   non-glanceable work like the daily-usage JSONL scan keeps idle energy
///   use low (issue #204).
/// - `.passive`: the app initiated the refresh without a click, e.g. when the
///   popover opens. Providers choose what that means: the default behaves
///   exactly like `.interactive`, Claude keeps attaching the daily-usage
///   report the popover renders, and Codex treats it like `.background` —
///   never spawning the CLI before the session was explicitly verified
///   (issue #216).
public enum RefreshKind: Sendable {
    case interactive
    case background
    case passive
}

/// Protocol defining what an AI provider is.
/// Each provider (Claude, Codex, Gemini) is a rich domain model implementing this protocol.
/// Providers are @Observable classes with their own state (isSyncing, snapshot, error).
///
/// `@MainActor` isolates the observable state (isSyncing/snapshot/lastError) to the main
/// actor so its cheap writes land on the same thread the readers (QuotaMonitor, SwiftUI)
/// run on. The heavy probe work stays off-main: `refresh()` suspends at the non-isolated
/// `await probe.probe()`, which runs on the global executor. A `@MainActor` class is
/// implicitly Sendable, so conformers no longer need `@unchecked Sendable`.
@MainActor
public protocol AIProvider: AnyObject, Sendable, Identifiable where ID == String {
    // MARK: - Identity

    /// Unique identifier for the provider (e.g., "claude", "codex", "gemini")
    var id: String { get }

    /// Display name for the provider (e.g., "Claude", "Codex", "Gemini")
    var name: String { get }

    /// CLI command used to invoke the provider
    var cliCommand: String { get }

    /// URL to the provider's usage/billing dashboard
    var dashboardURL: URL? { get }

    /// URL to the provider's status page
    var statusPageURL: URL? { get }

    /// Whether the provider is enabled (user can toggle this)
    var isEnabled: Bool { get set }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    var isSyncing: Bool { get }

    /// The current usage snapshot (nil if never refreshed or unavailable)
    var snapshot: UsageSnapshot? { get }

    /// The last error that occurred during refresh
    var lastError: Error? { get }

    // MARK: - Operations

    /// Checks if the provider is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool

    /// Refreshes the usage data and updates the snapshot.
    @discardableResult
    func refresh() async throws -> UsageSnapshot

    /// Refreshes the usage data for the given refresh kind and updates the
    /// snapshot. Interactive refreshes may do extra work (e.g. attaching the
    /// daily-usage report); background refreshes stay cheap (issue #204), and
    /// passive refreshes (popover open) may skip side-effectful probing
    /// (issue #216). A default implementation delegates to `refresh()`, so
    /// providers that don't distinguish the kinds need no extra code.
    @discardableResult
    func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot

    /// An optional lower bound this provider imposes on the *background* poll
    /// cadence, independent of the user's chosen interval. `nil` means the
    /// provider has no opinion. Claude in API mode returns 15 min to match its
    /// snapshot-cache TTL, so a fast user interval can't drive redundant HTTP
    /// (and 429s) in the background (issue #204).
    var backgroundRefreshFloor: Duration? { get }
}

// MARK: - Default Implementations

public extension AIProvider {
    /// Default: no status page
    var statusPageURL: URL? { nil }

    /// Default: background refreshes behave exactly like interactive ones. A
    /// provider only overrides this when it can legitimately do less work in the
    /// background. Keeps every existing conformer compiling unchanged.
    @discardableResult
    func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        try await refresh()
    }

    /// Default: no provider-imposed background cadence floor.
    var backgroundRefreshFloor: Duration? { nil }
}
