import Foundation

/// Represents an AI coding assistant provider that can be monitored.
/// This is a rich domain model that encapsulates provider-specific behavior.
public enum AIProvider: String, CaseIterable, Sendable, Equatable, Hashable {
    case claude
    case codex
    case gemini

    /// Human-readable display name
    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    /// CLI command used to invoke this provider
    public var cliCommand: String {
        rawValue
    }

    /// Whether this provider is enabled by default
    public var isEnabled: Bool {
        true
    }

    /// URL to the provider's usage dashboard
    public var dashboardURL: URL? {
        switch self {
        case .claude:
            URL(string: "https://console.anthropic.com/settings/billing")
        case .codex:
            URL(string: "https://chatgpt.com/codex/settings/usage")
        case .gemini:
            URL(string: "https://gemini.google.com")
        }
    }

    /// URL to check the provider's service status
    public var statusPageURL: URL? {
        switch self {
        case .claude:
            URL(string: "https://status.claude.com/")
        case .codex:
            URL(string: "https://status.openai.com/")
        case .gemini:
            URL(string: "https://aistudio.google.com/status")
        }
    }

    /// Label for the session-based quota
    public var sessionQuotaLabel: String {
        switch self {
        case .claude, .codex: "Session"
        case .gemini: "Pro"
        }
    }

    /// Label for the weekly quota
    public var weeklyQuotaLabel: String {
        switch self {
        case .claude, .codex: "Weekly"
        case .gemini: "Flash"
        }
    }

    /// Whether this provider supports model-specific limits (e.g., Opus for Claude)
    public var supportsModelSpecificLimits: Bool {
        switch self {
        case .claude: true
        case .codex, .gemini: false
        }
    }
}
