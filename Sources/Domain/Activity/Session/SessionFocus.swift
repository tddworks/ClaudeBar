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
/// *Bring a session forward*). Where it goes is the session's own answer
/// (`ClaudeSession.place`, `DoneRepo.place`); this only tells the port.
@MainActor
public final class SessionFocus {
    private let terminals: any TerminalFocus

    public init(terminals: any TerminalFocus) {
        self.terminals = terminals
    }

    /// Brings `session`'s terminal forward; nothing when it never said where it runs.
    /// Answers the work under way, for whoever wants to wait for it.
    @discardableResult
    public func bringForward(_ session: ClaudeSession) -> Task<Void, Never>? {
        go(to: session.place)
    }

    /// Brings forward the Done row's session that finished last.
    @discardableResult
    public func bringForward(_ repo: DoneRepo) -> Task<Void, Never>? {
        go(to: repo.place)
    }

    private func go(to place: TerminalPlace?) -> Task<Void, Never>? {
        guard let place else { return nil }
        let terminals = terminals
        return Task { await terminals.bringForward(place) }
    }
}
