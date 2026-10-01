import Foundation

/// The mode used by MistralProvider to fetch usage data.
/// Users can switch between local Vibe logs (default) and API modes in Settings.
public enum MistralProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use local Vibe session logs (`~/.vibe/logs/session/`) to calculate usage.
    /// This is the default mode and works without any API key.
    case localLogs

    /// Use the Mistral Code API to fetch Vibe Coding Plan usage percentage.
    /// Requires session cookies from chat.mistral.ai (MISTRAL_CHAT_COOKIE).
    case api

    /// Human-readable display name for the mode
    public var displayName: String {
        switch self {
        case .localLogs:
            return "Local Logs"
        case .api:
            return "Code API"
        }
    }

    /// Description of what this mode does
    public var description: String {
        switch self {
        case .localLogs:
            return "Token costs from ~/.vibe/logs/session/"
        case .api:
            return "Usage % via chat.mistral.ai Code API (session cookie)"
        }
    }
}