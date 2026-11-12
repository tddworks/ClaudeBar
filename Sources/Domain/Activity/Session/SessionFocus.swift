import Foundation
import Mockable

/// Where to bring a session forward: the terminal it runs in, and its folder
/// (Ghostty finds a terminal by the folder it is open in).
public struct TerminalPlace: Sendable, Equatable {
    public let terminal: SessionTerminal
    public let folder: String

    public init(terminal: SessionTerminal, folder: String) {
        self.terminal = terminal
        self.folder = folder
    }
}

/// Brings a terminal to the front, on the tab, pane or terminal that runs a
/// session when the terminal can be told; else the app alone.
@Mockable
public protocol TerminalFocus: Sendable {
    /// Brings `place` forward. A tab or terminal that has gone is not an
    /// error the person can act on: the app comes forward as it is.
    func bringForward(_ place: TerminalPlace) async
}

/// Brings the terminal of a session the person picked in the Claude Code card
/// or the notch to the front (docs/features/activity/session-hooks/design.md,
/// *Bring a session forward*).
@MainActor
public final class SessionFocus {
    private let sessions: SessionMonitor
    private let terminals: any TerminalFocus

    public init(sessions: SessionMonitor, terminals: any TerminalFocus) {
        self.sessions = sessions
        self.terminals = terminals
    }

    /// Where `session` would be brought forward; nil when it never said where it runs.
    public func place(of session: ClaudeSession) -> TerminalPlace? {
        guard session.canBringForward, let terminal = session.terminal else { return nil }
        return TerminalPlace(terminal: terminal, folder: session.cwd)
    }

    /// Where a Done row would be brought forward: its session that finished last.
    public func place(of repo: DoneRepo) -> TerminalPlace? {
        sessions.sessions.first { $0.id == repo.latestSessionId }.flatMap(place(of:))
    }

    /// Whether a Done row can be brought forward.
    public func canBringForward(_ repo: DoneRepo) -> Bool {
        place(of: repo) != nil
    }

    /// Brings `session`'s terminal forward; nothing when it never said where it runs.
    public func bringForward(_ session: ClaudeSession) {
        go(to: place(of: session))
    }

    /// Brings forward the Done row's session that finished last.
    public func bringForward(_ repo: DoneRepo) {
        go(to: place(of: repo))
    }

    private func go(to place: TerminalPlace?) {
        guard let place else { return }
        let terminals = terminals
        Task { await terminals.bringForward(place) }
    }
}
