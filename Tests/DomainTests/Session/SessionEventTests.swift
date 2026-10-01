import Testing
import Foundation
@testable import Domain

@Suite
struct SessionEventTests {
    @Test
    func `creates event with all fields`() {
        let date = Date()
        let event = SessionEvent(
            sessionId: "abc-123",
            eventName: .sessionStart,
            cwd: "/tmp/project",
            receivedAt: date
        )

        #expect(event.sessionId == "abc-123")
        #expect(event.eventName == .sessionStart)
        #expect(event.cwd == "/tmp/project")
        #expect(event.receivedAt == date)
    }

    @Test
    func `events with same values are equal`() {
        let date = Date()
        let event1 = SessionEvent(sessionId: "abc", eventName: .taskCompleted, cwd: "/tmp", receivedAt: date)
        let event2 = SessionEvent(sessionId: "abc", eventName: .taskCompleted, cwd: "/tmp", receivedAt: date)

        #expect(event1 == event2)
    }

    @Test
    func `events with different values are not equal`() {
        let date = Date()
        let event1 = SessionEvent(sessionId: "abc", eventName: .sessionStart, cwd: "/tmp", receivedAt: date)
        let event2 = SessionEvent(sessionId: "def", eventName: .sessionStart, cwd: "/tmp", receivedAt: date)

        #expect(event1 != event2)
    }

    @Test
    func `Codable round-trip preserves all fields`() throws {
        let date = Date()
        let original = SessionEvent(
            sessionId: "test-session",
            eventName: .subagentStart,
            cwd: "/Users/test/project",
            receivedAt: date
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionEvent.self, from: data)

        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.eventName == original.eventName)
        #expect(decoded.cwd == original.cwd)
    }

    @Test
    func `event from probe working directory is flagged as ClaudeBar probe`() {
        let event = SessionEvent(
            sessionId: "probe-1",
            eventName: .sessionEnd,
            cwd: "/Users/test/Library/Application Support/ClaudeBar/Probe"
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `event with trailing slash on probe directory is flagged as ClaudeBar probe`() {
        let event = SessionEvent(
            sessionId: "probe-2",
            eventName: .sessionStart,
            cwd: "/Users/test/Library/Application Support/ClaudeBar/Probe/"
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `event from a real project directory is not flagged as ClaudeBar probe`() {
        let event = SessionEvent(
            sessionId: "real-1",
            eventName: .sessionEnd,
            cwd: "/Users/test/code/my-project"
        )

        #expect(!event.isClaudeBarProbe)
    }

    @Test
    func `event from a directory merely named Probe is not flagged`() {
        let event = SessionEvent(
            sessionId: "real-2",
            eventName: .sessionEnd,
            cwd: "/Users/test/code/Probe"
        )

        #expect(!event.isClaudeBarProbe)
    }

    @Test
    func `all event names have correct raw values`() {
        #expect(SessionEvent.EventName.sessionStart.rawValue == "SessionStart")
        #expect(SessionEvent.EventName.sessionEnd.rawValue == "SessionEnd")
        #expect(SessionEvent.EventName.taskCompleted.rawValue == "TaskCompleted")
        #expect(SessionEvent.EventName.subagentStart.rawValue == "SubagentStart")
        #expect(SessionEvent.EventName.subagentStop.rawValue == "SubagentStop")
        #expect(SessionEvent.EventName.stop.rawValue == "Stop")
        #expect(SessionEvent.EventName.userPromptSubmit.rawValue == "UserPromptSubmit")
        #expect(SessionEvent.EventName.notification.rawValue == "Notification")
    }

    @Test
    func `message defaults to nil`() {
        let event = SessionEvent(sessionId: "s", eventName: .sessionStart, cwd: "/tmp")

        #expect(event.message == nil)
    }

    @Test
    func `a notification event carries the prompt Claude Code is blocked on`() {
        let event = SessionEvent(
            sessionId: "s",
            eventName: .notification,
            cwd: "/tmp",
            message: "Claude needs your permission to use Bash"
        )

        #expect(event.eventName == .notification)
        #expect(event.message == "Claude needs your permission to use Bash")
    }
}
