import Foundation

/// Where a Claude Code session runs: which terminal app, its iTerm2 session
/// and its tmux pane, read from what the terminal set in Claude Code's
/// environment. The hook passes those values on with every event.
///
/// nil (from `init?(environment:)`) when the environment said nothing usable:
/// a hook from before ClaudeBar sent them, or a session outside any terminal.
public struct SessionTerminal: Sendable, Equatable, Codable {
    /// The names of the environment variables that say where a session runs;
    /// the hook sends each one.
    public enum Variable: String, CaseIterable, Sendable {
        case termProgram = "TERM_PROGRAM"
        /// iTerm2 sets it, and unlike `TERM_PROGRAM` it survives tmux and ssh.
        case lcTerminal = "LC_TERMINAL"
        case iTermSessionId = "ITERM_SESSION_ID"
        case tmux = "TMUX"
        case tmuxPane = "TMUX_PANE"
    }

    /// The terminal app a session runs in.
    public enum App: Sendable, Hashable, Codable {
        case iTerm2
        case ghostty
        case terminal
        case warp
        case wezTerm
        /// A terminal known only by the name it gave itself.
        case other(String)
    }

    /// A tmux pane and the server that holds it.
    public struct TmuxPane: Sendable, Equatable, Codable {
        /// The pane's ID, e.g. `%3`.
        public let pane: String
        /// The server's socket path, when tmux said.
        public let socket: String?

        public init(pane: String, socket: String?) {
            self.pane = pane
            self.socket = socket
        }
    }

    /// The terminal app, when it is known. Inside tmux it is the terminal
    /// around tmux, when that said; nil when only the pane is known.
    public let app: App?
    /// The iTerm2 session's unique ID (the UUID part of `ITERM_SESSION_ID`).
    /// Only letters, digits and hyphens: anything else is not an ID.
    public let iTermSessionId: String?
    /// The tmux pane, when the session runs inside tmux.
    public let tmux: TmuxPane?

    public init(app: App?, iTermSessionId: String? = nil, tmux: TmuxPane? = nil) {
        self.app = app
        self.iTermSessionId = iTermSessionId
        self.tmux = tmux
    }

    /// Where a session runs, from the variables named in `Variable`; nil when
    /// they name neither an app nor a tmux pane.
    public init?(environment: [String: String]) {
        func value(_ variable: Variable) -> String? {
            let raw = environment[variable.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
            return raw.isEmpty ? nil : raw
        }

        let app = Self.app(termProgram: value(.termProgram), lcTerminal: value(.lcTerminal))
        let tmux = value(.tmuxPane).map { TmuxPane(pane: $0, socket: value(.tmux).flatMap(Self.socket(fromTmux:))) }
        guard app != nil || tmux != nil else { return nil }

        self.app = app
        self.iTermSessionId = app == .iTerm2 ? value(.iTermSessionId).flatMap(Self.uniqueId(fromITermSession:)) : nil
        self.tmux = tmux
    }

    private static func app(termProgram: String?, lcTerminal: String?) -> App? {
        if lcTerminal == "iTerm2" { return .iTerm2 }
        switch termProgram {
        case nil, "tmux", "screen": return nil
        case "iTerm.app": return .iTerm2
        case "ghostty": return .ghostty
        case "Apple_Terminal": return .terminal
        case "WarpTerminal": return .warp
        case "WezTerm": return .wezTerm
        case let name?: return .other(name)
        }
    }

    /// `w0t1p0:UUID` → `UUID`, the ID iTerm2's scripting calls `unique ID`.
    private static func uniqueId(fromITermSession value: String) -> String? {
        let id = value.split(separator: ":", maxSplits: 1).last.map(String.init) ?? value
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !id.isEmpty, id.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { return nil }
        return id
    }

    /// `TMUX` is `socket,pid,session`; the socket path may itself hold commas.
    private static func socket(fromTmux value: String) -> String? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return parts.first.map(String.init) }
        return parts.dropLast(2).joined(separator: ",")
    }
}
