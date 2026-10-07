package com.tddworks.claudebar.activity

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val NOW = 1_700_000_000.0

class SessionEventTest {
    private fun event(sessionId: String, eventName: SessionEvent.EventName, cwd: String, message: String? = null) =
        SessionEvent(sessionId = sessionId, eventName = eventName, cwd = cwd, receivedAtSeconds = NOW, message = message)

    @Test
    fun `should carry the session, what happened, the folder and when it arrived`() {
        val event = event("abc-123", SessionEvent.EventName.SESSION_START, "/tmp/project")

        assertEquals("abc-123", event.sessionId)
        assertEquals(SessionEvent.EventName.SESSION_START, event.eventName)
        assertEquals("/tmp/project", event.cwd)
        assertEquals(NOW, event.receivedAtSeconds)
    }

    @Test
    fun `should treat two reports of the same thing as the same event`() {
        assertEquals(
            event("abc", SessionEvent.EventName.TASK_COMPLETED, "/tmp"),
            event("abc", SessionEvent.EventName.TASK_COMPLETED, "/tmp"),
        )
    }

    @Test
    fun `should tell apart events from different sessions`() {
        assertNotEquals(
            event("abc", SessionEvent.EventName.SESSION_START, "/tmp"),
            event("def", SessionEvent.EventName.SESSION_START, "/tmp"),
        )
    }

    @Test
    fun `should keep the session, what happened and the folder when saved and read back`() {
        val original = event("test-session", SessionEvent.EventName.SUBAGENT_START, "/Users/test/project")

        val decoded = Json.decodeFromString<SessionEvent>(Json.encodeToString(original))

        assertEquals(original.sessionId, decoded.sessionId)
        assertEquals(original.eventName, decoded.eventName)
        assertEquals(original.cwd, decoded.cwd)
    }

    @Test
    fun `should count an event from ClaudeBar's own working folder as ClaudeBar's own run`() {
        val event = event("probe-1", SessionEvent.EventName.SESSION_END, "/Users/test/Library/Application Support/ClaudeBar/Probe")

        assertTrue(event.isClaudeBarProbe)
    }

    @Test
    fun `should count an event from ClaudeBar's own working folder as its own run even with a trailing slash`() {
        val event = event("probe-2", SessionEvent.EventName.SESSION_START, "/Users/test/Library/Application Support/ClaudeBar/Probe/")

        assertTrue(event.isClaudeBarProbe)
    }

    @Test
    fun `should count an event from the person's project as a real session`() {
        assertFalse(event("real-1", SessionEvent.EventName.SESSION_END, "/Users/test/code/my-project").isClaudeBarProbe)
    }

    @Test
    fun `should count an event from a project folder that merely shares the name Probe as a real session`() {
        assertFalse(event("real-2", SessionEvent.EventName.SESSION_END, "/Users/test/code/Probe").isClaudeBarProbe)
    }

    @Test
    fun `should count an event with no folder as ClaudeBar's own run (#222)`() {
        // The probe's hook payloads can arrive with cwd missing or reshaped by a CLI update;
        // without it the suffix filter let the probe leak back in as a Started/Finished pair.
        assertTrue(event("no-cwd-1", SessionEvent.EventName.SESSION_START, "").isClaudeBarProbe)
    }

    @Test
    fun `should count an event with a blank folder as ClaudeBar's own run`() {
        assertTrue(event("no-cwd-2", SessionEvent.EventName.SESSION_END, "   ").isClaudeBarProbe)
    }

    @Test
    fun `should know each event by the name Claude Code's hooks send`() {
        assertEquals("SessionStart", SessionEvent.EventName.SESSION_START.rawValue)
        assertEquals("SessionEnd", SessionEvent.EventName.SESSION_END.rawValue)
        assertEquals("TaskCompleted", SessionEvent.EventName.TASK_COMPLETED.rawValue)
        assertEquals("SubagentStart", SessionEvent.EventName.SUBAGENT_START.rawValue)
        assertEquals("SubagentStop", SessionEvent.EventName.SUBAGENT_STOP.rawValue)
        assertEquals("Stop", SessionEvent.EventName.STOP.rawValue)
        assertEquals("UserPromptSubmit", SessionEvent.EventName.USER_PROMPT_SUBMIT.rawValue)
        assertEquals("Notification", SessionEvent.EventName.NOTIFICATION.rawValue)
    }

    @Test
    fun `should carry no message when the hook sends none`() {
        assertNull(event("s", SessionEvent.EventName.SESSION_START, "/tmp").message)
    }

    @Test
    fun `should carry the prompt Claude Code is blocked on when it notifies`() {
        val event = event("s", SessionEvent.EventName.NOTIFICATION, "/tmp", message = "Claude needs your permission to use Bash")

        assertEquals(SessionEvent.EventName.NOTIFICATION, event.eventName)
        assertEquals("Claude needs your permission to use Bash", event.message)
    }
}
