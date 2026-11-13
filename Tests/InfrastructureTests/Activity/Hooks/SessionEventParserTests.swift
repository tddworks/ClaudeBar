import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

@Suite
struct SessionEventParserTests {
    @Test
    func `should recognise a session start with its session id and folder`() {
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
    func `should take the Claude Code process from the hook's header`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!, processId: "34901")

        #expect(event?.processId == 34901)
    }

    @Test
    func `should carry no process when the hook sent none or something that is not a number`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}
        """

        #expect(SessionEventParser.parse(json.data(using: .utf8)!)?.processId == nil)
        #expect(SessionEventParser.parse(json.data(using: .utf8)!, processId: "")?.processId == nil)
        #expect(SessionEventParser.parse(json.data(using: .utf8)!, processId: "$CLAUDE_PID")?.processId == nil)
    }

    @Test
    func `should recognise a completed task`() {
        let json = """
        {"session_id": "xyz", "hook_event_name": "TaskCompleted", "cwd": "/home/user/code"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .taskCompleted)
    }

    @Test
    func `should recognise a subagent starting`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SubagentStart", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .subagentStart)
    }

    @Test
    func `should recognise a subagent stopping`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SubagentStop", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .subagentStop)
    }

    @Test
    func `should recognise a turn that ended in an error, with what went wrong`() {
        let json = """
        {"session_id": "test", "hook_event_name": "StopFailure", "cwd": "/tmp", "error": "Connection error"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .stopFailure)
        #expect(event?.message == "Connection error")
    }

    @Test
    func `should recognise a session stopping`() {
        let json = """
        {"session_id": "test", "hook_event_name": "Stop", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .stop)
    }

    @Test
    func `should recognise a session ending`() {
        let json = """
        {"session_id": "test", "hook_event_name": "SessionEnd", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .sessionEnd)
    }

    @Test
    func `should recognise a submitted prompt`() {
        let json = """
        {"session_id": "test", "hook_event_name": "UserPromptSubmit", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .userPromptSubmit)
    }

    @Test
    func `should ignore an event that names no session`() {
        let json = """
        {"hook_event_name": "SessionStart", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `should ignore an event that names no event`() {
        let json = """
        {"session_id": "abc", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `should ignore an event it does not know`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "UnknownEvent", "cwd": "/tmp"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event == nil)
    }

    @Test
    func `should ignore a message that is not JSON`() {
        let data = "not json".data(using: .utf8)!

        let event = SessionEventParser.parse(data)

        #expect(event == nil)
    }

    @Test
    func `should leave the folder empty when the event names none`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "SessionStart"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.cwd == "")
    }

    @Test
    func `should still recognise an event that carries extra fields`() {
        let json = """
        {"session_id": "abc", "hook_event_name": "TaskCompleted", "cwd": "/tmp", "extra_field": "value", "number": 42}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event != nil)
        #expect(event?.sessionId == "abc")
    }

    @Test
    func `should read the transcript a session writes to`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "Stop", "cwd": "/tmp/project", "transcript_path": "/tmp/abc-123.jsonl"}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.transcriptPath == "/tmp/abc-123.jsonl")
    }

    @Test
    func `should read where a session runs from the hook`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "Stop", "cwd": "/tmp/project"}
        """

        let event = SessionEventParser.parse(
            json.data(using: .utf8)!,
            environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:ABC-123", "TMUX_PANE": ""]
        )

        #expect(event?.terminal == SessionTerminal(app: .iTerm2, iTermSessionId: "ABC-123"))
    }

    @Test
    func `should know nothing of where a session runs when the hook didn't say`() {
        let json = """
        {"session_id": "abc-123", "hook_event_name": "Stop", "cwd": "/tmp/project"}
        """

        #expect(SessionEventParser.parse(json.data(using: .utf8)!)?.terminal == nil)
    }

    // MARK: - Background tasks

    @Test
    func `should read the tasks still running when a turn ended`() {
        let json = """
        {"session_id": "s", "hook_event_name": "Stop", "cwd": "/code/replays",
         "background_tasks": [
           {"id": "b1", "type": "shell", "status": "running", "description": "rerun the replays", "command": "make replays"},
           {"id": "a1", "type": "subagent", "status": "running", "description": "review", "agent_type": "Explore"},
           {"id": "w1", "type": "workflow", "status": "running", "description": "audit", "name": "audit"}
         ],
         "session_crons": [{"id": "c1", "schedule": "0 9 * * *", "recurring": true, "prompt": "check"}]}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.backgroundTasks == [
            BackgroundTask(id: "b1", kind: .shell),
            BackgroundTask(id: "a1", kind: .agent),
            BackgroundTask(id: "w1", kind: .other),
        ])
    }

    @Test
    func `should say nothing of background tasks when the event doesn't`() {
        let json = """
        {"session_id": "s", "hook_event_name": "Stop", "cwd": "/code/replays"}
        """

        #expect(SessionEventParser.parse(json.data(using: .utf8)!)?.backgroundTasks == nil)
    }

    @Test
    func `should read no background tasks when none are running`() {
        let json = """
        {"session_id": "s", "hook_event_name": "Stop", "cwd": "/code/replays", "background_tasks": []}
        """

        #expect(SessionEventParser.parse(json.data(using: .utf8)!)?.backgroundTasks == [])
    }

    // MARK: - A question Claude asks

    @Test
    func `should read a question Claude asks`() {
        let json = """
        {"session_id": "s", "hook_event_name": "PreToolUse", "cwd": "/code/claudebar", "tool_name": "AskUserQuestion",
         "tool_input": {"questions": [
           {"question": "Which design should we build?", "header": "Design", "multiSelect": false, "options": []},
           {"question": "Which branch?", "header": "Branch", "multiSelect": false, "options": []}
         ]}}
        """

        let event = SessionEventParser.parse(json.data(using: .utf8)!)

        #expect(event?.eventName == .preToolUse)
        #expect(event?.message == "Which design should we build?")
    }

    @Test
    func `should read a question answered`() {
        let json = """
        {"session_id": "s", "hook_event_name": "PostToolUse", "cwd": "/code/claudebar", "tool_name": "AskUserQuestion",
         "tool_input": {"questions": [{"question": "Which design should we build?"}]}, "tool_response": {}}
        """

        #expect(SessionEventParser.parse(json.data(using: .utf8)!)?.eventName == .postToolUse)
    }
}
