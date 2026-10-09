import Testing
import Foundation
@testable import Domain

@Suite
struct SessionEventTests {
    @Test
    func `should carry the session, what happened, the folder and when it arrived`() {
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
    func `should treat two reports of the same thing as the same event`() {
        let date = Date()
        let event1 = SessionEvent(sessionId: "abc", eventName: .taskCompleted, cwd: "/tmp", receivedAt: date)
        let event2 = SessionEvent(sessionId: "abc", eventName: .taskCompleted, cwd: "/tmp", receivedAt: date)

        #expect(event1 == event2)
    }

    @Test
    func `should tell apart events from different sessions`() {
        let date = Date()
        let event1 = SessionEvent(sessionId: "abc", eventName: .sessionStart, cwd: "/tmp", receivedAt: date)
        let event2 = SessionEvent(sessionId: "def", eventName: .sessionStart, cwd: "/tmp", receivedAt: date)

        #expect(event1 != event2)
    }

    @Test
    func `should carry the titles read for it and keep everything else`() {
        let date = Date()
        let event = SessionEvent(
            sessionId: "abc", eventName: .stop, cwd: "/tmp/project", receivedAt: date,
            message: "Done", processId: 42, transcriptPath: "/tmp/abc.jsonl"
        )
        let titles = TranscriptTitles(named: "Session names", generated: "Pull latest main")

        let titled = event.titled(titles)

        #expect(titled == SessionEvent(
            sessionId: "abc", eventName: .stop, cwd: "/tmp/project", receivedAt: date,
            message: "Done", processId: 42, transcriptPath: "/tmp/abc.jsonl", titles: titles
        ))
    }

    @Test
    func `should keep the session, what happened and the folder when saved and read back`() throws {
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
    func `should count an event from ClaudeBar's own working folder as ClaudeBar's own run`() {
        let event = SessionEvent(
            sessionId: "probe-1",
            eventName: .sessionEnd,
            cwd: "/Users/test/Library/Application Support/ClaudeBar/Probe"
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `should count an event from ClaudeBar's own working folder as its own run even with a trailing slash`() {
        let event = SessionEvent(
            sessionId: "probe-2",
            eventName: .sessionStart,
            cwd: "/Users/test/Library/Application Support/ClaudeBar/Probe/"
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `should count an event from the person's project as a real session`() {
        let event = SessionEvent(
            sessionId: "real-1",
            eventName: .sessionEnd,
            cwd: "/Users/test/code/my-project"
        )

        #expect(!event.isClaudeBarProbe)
    }

    @Test
    func `should count an event from a project folder that merely shares the name Probe as a real session`() {
        let event = SessionEvent(
            sessionId: "real-2",
            eventName: .sessionEnd,
            cwd: "/Users/test/code/Probe"
        )

        #expect(!event.isClaudeBarProbe)
    }

    @Test
    func `should count an event with no folder as ClaudeBar's own run (#222)`() {
        // The probe's hook payloads can arrive with cwd missing or reshaped by
        // a CLI update; without it the suffix filter let the probe leak back
        // in as a "Claude Code Started/Finished" pair (#222).
        let event = SessionEvent(
            sessionId: "no-cwd-1",
            eventName: .sessionStart,
            cwd: ""
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `should count an event with a blank folder as ClaudeBar's own run`() {
        let event = SessionEvent(
            sessionId: "no-cwd-2",
            eventName: .sessionEnd,
            cwd: "   "
        )

        #expect(event.isClaudeBarProbe)
    }

    @Test
    func `should know each event by the name Claude Code's hooks send`() {
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
    func `should carry no message when the hook sends none`() {
        let event = SessionEvent(sessionId: "s", eventName: .sessionStart, cwd: "/tmp")

        #expect(event.message == nil)
    }

    @Test
    func `should carry the prompt Claude Code is blocked on when it notifies`() {
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
