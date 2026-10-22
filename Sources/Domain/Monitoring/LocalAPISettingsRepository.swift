import Foundation

/// Constants for the local API and MCP server.
public enum LocalAPIConstants {
    /// The port the local API and MCP server listens on, on 127.0.0.1 only —
    /// beside the hook server's 19847, one number apart. If another process
    /// holds it, the server takes a free port and writes the real number to
    /// `~/.claudebar/api-port`; a launcher that needs the real port reads the
    /// file, as the hook scripts do.
    public static let defaultPort: UInt16 = 19848
}

/// Settings for the local API and MCP server.
/// Standalone protocol (not extending `ProviderSettingsRepository`), as
/// `HookSettingsRepository` is: the API is a surface, not a provider. One
/// switch: off means no listener exists at all.
public protocol LocalAPISettingsRepository: Sendable {
    /// Whether the local API server is on (default: off).
    func isLocalAPIEnabled() -> Bool

    /// Turns the local API server on or off.
    func setLocalAPIEnabled(_ enabled: Bool)
}
