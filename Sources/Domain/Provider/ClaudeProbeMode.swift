import Foundation

/// The mode used by ClaudeProvider to fetch usage data.
/// Users can switch between CLI (default) and API modes in Settings.
public enum ClaudeProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Use the Claude CLI (`claude /usage`) to fetch usage data.
    /// This is the default mode and works without additional configuration.
    case cli

    /// Use the Claude OAuth API to fetch usage data directly.
    /// Requires valid OAuth credentials in ~/.claude/.credentials.json or Keychain.
    /// Faster than CLI mode as it doesn't spawn a subprocess.
    case api

    /// Human-readable display name for the mode
    public var displayName: String {
        switch self {
        case .cli:
            return "CLI"
        case .api:
            return "API"
        }
    }

    /// Description of what this mode does
    public var description: String {
        switch self {
        case .cli:
            return "Uses claude /usage command"
        case .api:
            return "Calls Anthropic API directly"
        }
    }
}
