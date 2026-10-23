import Foundation

/// Settings for the local API and MCP server.
/// Standalone protocol (not extending `ProviderSettingsRepository`), as
/// `HookSettingsRepository` is: the API is a destination, not a provider. One
/// switch: off means no listener exists at all.
public protocol LocalAPISettingsRepository: Sendable {
    /// Whether the local API server is on (default: off).
    func isLocalAPIEnabled() -> Bool

    /// Turns the local API server on or off.
    func setLocalAPIEnabled(_ enabled: Bool)
}
