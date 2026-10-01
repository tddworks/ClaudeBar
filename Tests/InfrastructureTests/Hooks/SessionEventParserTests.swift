import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite
struct SessionEventParserTests {
    @Test
    func `parses valid SessionStart event`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event != nil)
        #expect(event?.sessionId == "abc-123")
        #expect(event?.eventName == .sessionStart)
        #expect(event?.cwd == "/tmp/project")
    }

    @Test
    func `parses valid TaskCompleted event`() {
        let json = """
        {"session_id": "xyz", "hook_event_name": "TaskCompleted", "cwd": "/home/user/code"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .taskCompleted)
    }

    @Test
    func `parses valid SubagentStart event`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SubagentStart", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .subagentStart)
    }

    @Test
    func `parses valid SubagentStop event`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SubagentStop", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .subagentStop)
    }

    @Test
    func `parses valid Stop event`() {
        let json = """
        {"session_id": "test", "hook_event_name": "Stop", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .stop)
    }

    @Test
    func `parses valid SessionEnd event`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SessionEnd", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .sessionEnd)
    }

    @Test
    func `parses valid UserPromptSubmit event`() {
        let json = """
        {"session_id": "test", "hook_event_name": "UserPromptSubmit", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .userPromptSubmit)
    }

    @Test
    func `returns nil for missing session_id`() {
        let json = """
        {"hook_event_name": "SessionStart", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `returns nil for missing hook_event_name`() {
        let json = """
        {"session_id": "abc", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `returns nil for unknown event name`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "UnknownEvent", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `returns nil for invalid JSON`() {
        let data = "not json".data(using: .utf8)!

        let event = SessionEventParser.parse(data)

        #expect(event == nil)
    }

    @Test
    func `uses empty string for missing cwd`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "SessionStart"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.cwd == "")
    }

    @Test
    func `ignores extra fields in payload`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "TaskCompleted", "cwd": "/tmp", "extra_field": "value", "number": 42}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event != nil)
        #expect(event?.sessionId == "abc")
    }
}
