import Foundation
import Combine

/// Protocol defining what an AI provider is.
/// Each provider (Claude, Codex, Gemini) is a rich domain model implementing this protocol.
/// Providers are ObservableObject classes with their own state (isSyncing, snapshot, error).
/// Providers must be Sendable (use @unchecked Sendable for ObservableObject classes).
public protocol AIProvider: AnyObject, ObservableObject, Sendable, Identifiable where ID == String {
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
}

// MARK: - Default Implementations

public extension AIProvider {
    /// Default: no status page
    var statusPageURL: URL? { nil }
}

import Mockable

/// Protocol defining how to probe for usage data.
/// This is an internal implementation detail - callers use AIProvider.refresh() instead.
@Mockable
public protocol UsageProbe: Sendable {
    /// Fetches the current usage snapshot
    func probe() async throws -> UsageSnapshot

    /// Checks if the probe is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool
}
