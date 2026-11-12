import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
@MainActor
struct SessionFocusTests {
    private let iTerm = SessionTerminal(app: .iTerm2, iTermSessionId: "ABC")

    private func focus(over monitor: SessionMonitor) -> SessionFocus {
        SessionFocus(sessions: monitor, terminals: MockTerminalFocus())
    }

    @Test
    func `should bring forward the terminal of the session clicked`() {
        let monitor = SessionMonitor()
        monitor.processEvent(SessionEvent(sessionId: "s", eventName: .notification, cwd: "/code/tinyshop", terminal: iTerm))

        let place = focus(over: monitor).place(of: monitor.sessions[0])

        #expect(place == TerminalPlace(terminal: iTerm, folder: "/code/tinyshop"))
    }

    @Test
    func `should bring forward the latest of a folded repo`() {
        let monitor = SessionMonitor()
        let start = Date(timeIntervalSince1970: 1_000)
        let ghostty = SessionTerminal(app: .ghostty)
        monitor.processEvent(SessionEvent(sessionId: "early", eventName: .stop, cwd: "/code/claudebar", receivedAt: start, terminal: iTerm))
        monitor.processEvent(SessionEvent(sessionId: "late", eventName: .stop, cwd: "/code/claudebar", receivedAt: start.addingTimeInterval(60), terminal: ghostty))

        let place = focus(over: monitor).place(of: monitor.doneByRepo[0])

        #expect(place == TerminalPlace(terminal: ghostty, folder: "/code/claudebar"))
    }

    @Test
    func `should have nowhere to go for a session that never said where it runs`() {
        let monitor = SessionMonitor()
        monitor.processEvent(SessionEvent(sessionId: "s", eventName: .stop, cwd: "/code/catalog"))

        let focus = focus(over: monitor)

        #expect(focus.place(of: monitor.sessions[0]) == nil)
        #expect(focus.place(of: monitor.doneByRepo[0]) == nil)
    }
}
