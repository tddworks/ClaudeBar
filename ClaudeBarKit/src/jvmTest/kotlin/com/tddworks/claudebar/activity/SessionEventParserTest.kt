package com.tddworks.claudebar.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

private const val NOW = 1_700_000_000.0

class SessionEventParserTest {
    private fun parse(json: String, processId: String? = null) = SessionEventParser.parse(json, NOW, processId)

    @Test
    fun `should recognise a session start with its session id and folder`() {
        val event = parse("""{"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}""")

        assertNotNull(event)
        assertEquals("abc-123", event?.sessionId)
        assertEquals(SessionEvent.EventName.SESSION_START, event?.eventName)
        assertEquals("/tmp/project", event?.cwd)
        assertEquals(NOW, event?.receivedAtSeconds)
    }

    @Test
    fun `should take the Claude Code process from the hook's header`() {
        val event = parse("""{"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}""", processId = "34901")

        assertEquals(34901, event?.processId)
    }

    @Test
    fun `should carry no process when the hook sent none or something that is not a number`() {
        val json = """{"session_id": "abc-123", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}"""

        assertNull(parse(json)?.processId)
        assertNull(parse(json, processId = "")?.processId)
        assertNull(parse(json, processId = "\$CLAUDE_PID")?.processId)
    }

    @Test
    fun `should recognise a completed task`() {
        val event = parse("""{"session_id": "xyz", "hook_event_name": "TaskCompleted", "cwd": "/home/user/code"}""")

        assertEquals(SessionEvent.EventName.TASK_COMPLETED, event?.eventName)
    }

    @Test
    fun `should recognise a subagent starting`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "SubagentStart", "cwd": "/tmp"}""")

        assertEquals(SessionEvent.EventName.SUBAGENT_START, event?.eventName)
    }

    @Test
    fun `should recognise a subagent stopping`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "SubagentStop", "cwd": "/tmp"}""")

        assertEquals(SessionEvent.EventName.SUBAGENT_STOP, event?.eventName)
    }

    @Test
    fun `should recognise a turn that ended in an error, with what went wrong`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "StopFailure", "cwd": "/tmp", "error": "Connection error"}""")

        assertEquals(SessionEvent.EventName.STOP_FAILURE, event?.eventName)
        assertEquals("Connection error", event?.message)
    }

    @Test
    fun `should recognise a session stopping`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "Stop", "cwd": "/tmp"}""")

        assertEquals(SessionEvent.EventName.STOP, event?.eventName)
    }

    @Test
    fun `should recognise a session ending`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "SessionEnd", "cwd": "/tmp"}""")

        assertEquals(SessionEvent.EventName.SESSION_END, event?.eventName)
    }

    @Test
    fun `should recognise a submitted prompt`() {
        val event = parse("""{"session_id": "test", "hook_event_name": "UserPromptSubmit", "cwd": "/tmp"}""")

        assertEquals(SessionEvent.EventName.USER_PROMPT_SUBMIT, event?.eventName)
    }

    @Test
    fun `should ignore an event that names no session`() {
        assertNull(parse("""{"hook_event_name": "SessionStart", "cwd": "/tmp"}"""))
    }

    @Test
    fun `should ignore an event that names no event`() {
        assertNull(parse("""{"session_id": "abc", "cwd": "/tmp"}"""))
    }

    @Test
    fun `should ignore an event it does not know`() {
        assertNull(parse("""{"session_id": "abc", "hook_event_name": "UnknownEvent", "cwd": "/tmp"}"""))
    }

    @Test
    fun `should ignore a message that is not JSON`() {
        assertNull(parse("not json"))
    }

    @Test
    fun `should leave the folder empty when the event names none`() {
        val event = parse("""{"session_id": "abc", "hook_event_name": "SessionStart"}""")

        assertEquals("", event?.cwd)
    }

    @Test
    fun `should still recognise an event that carries extra fields`() {
        val event = parse("""{"session_id": "abc", "hook_event_name": "TaskCompleted", "cwd": "/tmp", "extra_field": "value", "number": 42}""")

        assertNotNull(event)
        assertEquals("abc", event?.sessionId)
    }
}
