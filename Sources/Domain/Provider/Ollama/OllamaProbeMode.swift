import Foundation

/// The mode used by `OllamaProvider` to fetch usage data.
///
/// Ollama Pro / Ollama Cloud is a paid subscription with two supported
/// authentication flavors:
///
/// - **API**: a long-lived `OLLAMA_API_KEY` (or one entered in Settings)
///   sent as a `Bearer` token. This is the most reliable path and the
///   default for new installs.
/// - **Web**: a browser session cookie (`__Secure-next-auth.session-token`
///   and friends) read from the user's browser via SweetCookieKit. Useful
///   when the user only logs in via the website and does not have an API
///   key handy.
///
/// Users can switch between modes in the Settings UI.
public enum OllamaProbeMode: String, Sendable, Equatable, CaseIterable {
    /// Calls the Ollama API directly with a Bearer token.
    /// Requires either an `OLLAMA_API_KEY` environment variable or an
    /// API key entered in Settings.
    case api

    /// Scrapes the authenticated `ollama.com/settings` HTML using the
    /// session cookie from the user's browser.
    case web

    /// Human-readable display name for the mode.
    public var displayName: String {
        switch self {
        case .api:
            return "API"
        case .web:
            return "Web"
        }
    }

    /// Short description of what this mode does.
    public var description: String {
        switch self {
        case .api:
            return "Uses an Ollama API key (Bearer token)"
        case .web:
            return "Uses the ollama.com session cookie from your browser"
        }
    }
}
