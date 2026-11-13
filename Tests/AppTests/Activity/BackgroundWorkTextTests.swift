import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// What a row says a session left running in the background.
@Suite
struct BackgroundWorkTextTests {
    private func session(leaving tasks: [BackgroundTask]) -> ClaudeSession {
        var session = ClaudeSession(id: "s", cwd: "/code/replays")
        session.stop(at: Date(), leaving: tasks)
        return session
    }

    @Test
    func `should name one kind of work by what it is`() {
        #expect(session(leaving: [BackgroundTask(id: "b1", kind: .shell)]).backgroundWorkText == "1 shell")
        #expect(session(leaving: [BackgroundTask(id: "a1", kind: .agent), BackgroundTask(id: "a2", kind: .agent)]).backgroundWorkText == "2 agents")
    }

    @Test
    func `should call work of several kinds tasks`() {
        let tasks = [BackgroundTask(id: "b1", kind: .shell), BackgroundTask(id: "a1", kind: .agent), BackgroundTask(id: "m1", kind: .other)]

        #expect(session(leaving: tasks).backgroundWorkText == "3 tasks")
    }

    @Test
    func `should say nothing when no work runs`() {
        #expect(session(leaving: []).backgroundWorkText == nil)
    }
}
