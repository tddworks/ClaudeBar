import Testing
import Foundation
import Mockable
@testable import Domain

/// Where a click goes is the session's own answer (`ClaudeSession.place`,
/// `DoneRepo.place`); `SessionFocus` hands it to the terminal. These read
/// where the terminal ended up, through a fake that records it.
@Suite
@MainActor
struct SessionFocusTests {
    private let iTerm = SessionTerminal(app: .iTerm2, iTermSessionId: "ABC")

    /// Where the terminal was asked to come forward.
    private final class Shown: @unchecked Sendable { var places: [TerminalPlace] = [] }

    private func focus(showing shown: Shown) -> SessionFocus {
        let terminals = MockTerminalFocus()
        given(terminals).bringForward(.any).willProduce { @Sendable place in shown.places.append(place) }
        return SessionFocus(terminals: terminals)
    }

    @Test
    func `should bring the clicked session's terminal to the front`() async {
        let monitor = SessionMonitor()
        monitor.processEvent(SessionEvent(sessionId: "s", eventName: .notification, cwd: "/code/tinyshop", terminal: iTerm))
        let shown = Shown()

        await focus(showing: shown).bringForward(monitor.sessions[0])?.value

        #expect(shown.places == [TerminalPlace(terminal: iTerm, folder: "/code/tinyshop")])
    }

    @Test
    func `should bring the latest session of a clicked folded repo to the front`() async {
        let monitor = SessionMonitor()
        let start = Date(timeIntervalSince1970: 1_000)
        let ghostty = SessionTerminal(app: .ghostty)
        monitor.processEvent(SessionEvent(sessionId: "early", eventName: .stop, cwd: "/code/claudebar", receivedAt: start, terminal: iTerm))
        monitor.processEvent(SessionEvent(sessionId: "late", eventName: .stop, cwd: "/code/claudebar", receivedAt: start.addingTimeInterval(60), terminal: ghostty))
        let shown = Shown()

        await focus(showing: shown).bringForward(monitor.doneByRepo[0])?.value

        #expect(shown.places == [TerminalPlace(terminal: ghostty, folder: "/code/claudebar")])
    }

    @Test
    func `should bring nothing forward when the session never said where it runs`() async {
        let monitor = SessionMonitor()
        monitor.processEvent(SessionEvent(sessionId: "s", eventName: .stop, cwd: "/code/catalog"))
        let shown = Shown()
        let focus = focus(showing: shown)

        await focus.bringForward(monitor.sessions[0])?.value
        await focus.bringForward(monitor.doneByRepo[0])?.value

        #expect(shown.places.isEmpty)
    }
}
