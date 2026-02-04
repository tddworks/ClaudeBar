import Foundation

/// The mode used by CodexProvider to fetch usage data.
/// Users can switch between RPC (default) and API modes in Settings.
public enum CodexProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use the Codex RPC client (`codex app-server`) to fetch usage data.
    /// This is the default mode and works via JSON-RPC over stdin/stdout.
    case rpc

    /// Use the ChatGPT backend API to fetch usage data directly.
    /// Requires valid OAuth credentials in ~/.codex/auth.json.
    /// Faster than RPC mode as it doesn't spawn a subprocess.
    case api

    /// Human-readable display name for the mode
    public var displayName: String {
        switch self {
        case .rpc:
            return "RPC"
        case .api:
            return "API"
        }
    }

    /// Description of what this mode does
    public var description: String {
        switch self {
        case .rpc:
            return "Uses codex app-server RPC"
        case .api:
            return "Calls ChatGPT API directly"
        }
    }
}
