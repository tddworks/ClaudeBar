package com.tddworks.claudebar.activity

import com.tddworks.claudebar.activity.SessionEvent.EventName
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val START = 1_700_000_000.0

class SessionMonitorTest {
    /** Like Swift's `Date()` default: each event without a time arrives a moment after the last. */
    private var clock = START

    private fun makeEvent(
        sessionId: String = "test-session",
        eventName: EventName,
        cwd: String = "/tmp/project",
        receivedAt: Double? = null,
        message: String? = null,
        processId: Int? = null,
    ): SessionEvent = SessionEvent(
        sessionId = sessionId,
        eventName = eventName,
        cwd = cwd,
        receivedAtSeconds = receivedAt ?: (clock + 0.001).also { clock = it },
        message = message,
        processId = processId,
    )

    /** A Mac on which only the given Claude Code processes are still running. */
    private fun processes(running: Set<Int>) = ProcessLiveness { it in running }

    private fun session(id: String, monitor: SessionMonitor): Session? = monitor.sessions.firstOrNull { it.id == id }

    // Session lifecycle

    @Test
    fun `should show no session and no recent sessions before Claude Code starts one`() {
        val monitor = SessionMonitor()

        assertNull(monitor.activeSession)
        assertFalse(monitor.hasActiveSession)
        assertTrue(monitor.sessions.isEmpty())
        assertTrue(monitor.recentSessions.isEmpty())
    }

    @Test
    fun `should show a session in its folder, idle until the first prompt, when Claude Code starts one`() {
        // A session that has just opened sits at its prompt; it is not working, and it has not
        // finished anything either, so the notch has nothing to flash.
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))

        assertNotNull(monitor.activeSession)
        assertEquals("test-session", monitor.activeSession?.id)
        assertEquals("/tmp/project", monitor.activeSession?.cwd)
        assertEquals(Session.Phase.STOPPED, monitor.activeSession?.phase)
        assertNull(monitor.activeSession?.finishedAtSeconds)
        assertTrue(monitor.hasActiveSession)
    }

    @Test
    fun `should show the session working once the person sends the first prompt`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))

        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))

        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
    }

    @Test
    fun `should keep a working session working when Claude Code starts it again mid-turn, as on compaction`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))

        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
    }

    @Test
    fun `should move the session to recent sessions as ended when Claude Code ends it`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START, receivedAt = START))
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_END, receivedAt = START + 60))

        assertNull(monitor.activeSession)
        assertFalse(monitor.hasActiveSession)
        assertEquals(1, monitor.recentSessions.size)
        assertEquals("test-session", monitor.recentSessions.first().id)
        assertEquals(Session.Phase.ENDED, monitor.recentSessions.first().phase)
    }

    @Test
    fun `should keep the running session when another session ends`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_END))

        assertEquals("session-1", monitor.activeSession?.id)
        assertTrue(monitor.recentSessions.isEmpty())
    }

    // Several sessions

    @Test
    fun `should keep the first session running when a second one starts`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_START))

        assertEquals(listOf("session-1", "session-2"), monitor.sessions.map { it.id })
        assertTrue(monitor.recentSessions.isEmpty())
    }

    @Test
    fun `should pick up a session that was running before ClaudeBar started from its next event`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "older", eventName = EventName.USER_PROMPT_SUBMIT, cwd = "/tmp/older"))

        assertEquals("older", monitor.activeSession?.id)
        assertEquals("/tmp/older", monitor.activeSession?.cwd)
        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
    }

    @Test
    fun `should pick up a session as done when its first event does not show a turn underway`() {
        // A SubagentStop or TaskCompleted says nothing about whether the turn is still going;
        // claiming "Working" would stick until the next prompt.
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "late-agent", eventName = EventName.SUBAGENT_STOP))
        monitor.processEvent(makeEvent(sessionId = "late-task", eventName = EventName.TASK_COMPLETED))
        monitor.processEvent(makeEvent(sessionId = "prompted", eventName = EventName.USER_PROMPT_SUBMIT))
        monitor.processEvent(makeEvent(sessionId = "agent", eventName = EventName.SUBAGENT_START))

        assertEquals(Session.Phase.STOPPED, session("late-agent", monitor)?.phase)
        assertEquals(Session.Phase.STOPPED, session("late-task", monitor)?.phase)
        assertEquals(1, session("late-task", monitor)?.completedTaskCount)
        assertEquals(Session.Phase.ACTIVE, session("prompted", monitor)?.phase)
        assertEquals(Session.Phase.SUBAGENTS_WORKING, session("agent", monitor)?.phase)
    }

    @Test
    fun `should keep following an earlier session after a newer one starts`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.STOP))

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SUBAGENT_START))

        assertEquals("session-1", monitor.activeSession?.id)
        assertEquals(Session.Phase.SUBAGENTS_WORKING, monitor.activeSession?.phase)
    }

    @Test
    fun `should show the session that needs the person ahead of ones that are working`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "blocked", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "blocked", eventName = EventName.NOTIFICATION))

        monitor.processEvent(makeEvent(sessionId = "busy", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "busy", eventName = EventName.SUBAGENT_START))

        assertEquals("blocked", monitor.activeSession?.id)
    }

    @Test
    fun `should show a working session ahead of a stopped one that spoke last`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "busy", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "busy", eventName = EventName.USER_PROMPT_SUBMIT))
        monitor.processEvent(makeEvent(sessionId = "idle", eventName = EventName.SESSION_START))

        monitor.processEvent(makeEvent(sessionId = "idle", eventName = EventName.STOP))

        assertEquals("busy", monitor.activeSession?.id)
    }

    @Test
    fun `should show the session heard from last when several are in the same phase`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START, receivedAt = START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_START, receivedAt = START + 1))

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.USER_PROMPT_SUBMIT, receivedAt = START + 2))

        assertEquals("session-1", monitor.activeSession?.id)
    }

    @Test
    fun `should keep the other sessions running when one ends`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_START))

        monitor.processEvent(makeEvent(sessionId = "session-2", eventName = EventName.SESSION_END))

        assertEquals("session-1", monitor.activeSession?.id)
        assertEquals(listOf("session-2"), monitor.recentSessions.map { it.id })
    }

    @Test
    fun `should keep a session's progress when Claude Code starts it again`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.TASK_COMPLETED))

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))

        assertEquals(1, monitor.sessions.size)
        assertEquals(1, monitor.activeSession?.completedTaskCount)
        assertTrue(monitor.recentSessions.isEmpty())
    }

    @Test
    fun `should rank sessions by how much they need the person, then by who spoke last`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "idle", eventName = EventName.SESSION_START, receivedAt = START))
        monitor.processEvent(makeEvent(sessionId = "idle", eventName = EventName.STOP, receivedAt = START + 1))
        monitor.processEvent(makeEvent(sessionId = "active-old", eventName = EventName.SESSION_START, receivedAt = START + 2))
        monitor.processEvent(makeEvent(sessionId = "agents", eventName = EventName.SESSION_START, receivedAt = START + 3))
        monitor.processEvent(makeEvent(sessionId = "agents", eventName = EventName.SUBAGENT_START, receivedAt = START + 4))
        monitor.processEvent(makeEvent(sessionId = "blocked", eventName = EventName.SESSION_START, receivedAt = START + 5))
        monitor.processEvent(makeEvent(sessionId = "blocked", eventName = EventName.NOTIFICATION, receivedAt = START + 6))
        monitor.processEvent(makeEvent(sessionId = "active-new", eventName = EventName.SESSION_START, receivedAt = START + 7))

        assertEquals(listOf("blocked", "agents", "active-new", "active-old", "idle"), monitor.sessionsByProminence.map { it.id })
        assertEquals(listOf("idle", "active-old", "agents", "blocked", "active-new"), monitor.sessions.map { it.id })
    }

    // Sessions whose Claude Code process is gone

    @Test
    fun `should end a session whose Claude Code process is gone, keeping the ones still running`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "alive", eventName = EventName.SESSION_START, receivedAt = START, processId = 100))
        monitor.processEvent(makeEvent(sessionId = "killed", eventName = EventName.SESSION_START, receivedAt = START, processId = 200))

        val now = START + 60
        monitor.endSessionsWhoseProcessIsGone(processes(running = setOf(100)), atSeconds = now)

        assertEquals(listOf("alive"), monitor.sessions.map { it.id })
        assertEquals(listOf("killed"), monitor.recentSessions.map { it.id })
        assertEquals(Session.Phase.ENDED, monitor.recentSessions.first().phase)
        assertEquals(now, monitor.recentSessions.first().endedAtSeconds)
    }

    @Test
    fun `should keep a session that never said which process it runs in`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "unknown-pid", eventName = EventName.SESSION_START))

        monitor.endSessionsWhoseProcessIsGone(processes(running = emptySet()), atSeconds = START + 60)

        assertEquals(listOf("unknown-pid"), monitor.sessions.map { it.id })
    }

    @Test
    fun `should learn a session's process from a later event when the first one had none`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT, processId = 300))

        monitor.endSessionsWhoseProcessIsGone(processes(running = emptySet()), atSeconds = START + 60)

        assertTrue(monitor.sessions.isEmpty())
        assertEquals(300, monitor.recentSessions.first().processId)
    }

    // Task tracking

    @Test
    fun `should count each task Claude Code finishes in the session`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.TASK_COMPLETED))
        monitor.processEvent(makeEvent(eventName = EventName.TASK_COMPLETED))

        assertEquals(2, monitor.activeSession?.completedTaskCount)
    }

    @Test
    fun `should count a task for the session that finished it, not the others`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "other", eventName = EventName.TASK_COMPLETED))

        assertEquals(0, session("session-1", monitor)?.completedTaskCount)
        assertEquals(1, session("other", monitor)?.completedTaskCount)
    }

    // Subagent tracking

    @Test
    fun `should show agents working when a subagent starts in the session`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))

        assertEquals(Session.Phase.SUBAGENTS_WORKING, monitor.activeSession?.phase)
        assertEquals(1, monitor.activeSession?.activeSubagentCount)
    }

    @Test
    fun `should go back to active when the session's last subagent stops`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_STOP))

        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
        assertEquals(0, monitor.activeSession?.activeSubagentCount)
    }

    @Test
    fun `should keep two agents working when one of three subagents stops`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_STOP))

        assertEquals(2, monitor.activeSession?.activeSubagentCount)
        assertEquals(Session.Phase.SUBAGENTS_WORKING, monitor.activeSession?.phase)
    }

    // Stop

    @Test
    fun `should show the session done when its turn ends in an error, as after the Mac slept`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START, receivedAt = START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START, receivedAt = START))

        val failedAt = START + 3600
        monitor.processEvent(makeEvent(eventName = EventName.STOP_FAILURE, receivedAt = failedAt, message = "Connection error"))

        assertEquals(Session.Phase.STOPPED, monitor.activeSession?.phase)
        assertEquals(0, monitor.activeSession?.activeSubagentCount)
        assertEquals(failedAt, monitor.activeSession?.stoppedAtSeconds)
    }

    @Test
    fun `should show the session stopped with no agents when Claude stops`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        monitor.processEvent(makeEvent(eventName = EventName.STOP))

        assertEquals(Session.Phase.STOPPED, monitor.activeSession?.phase)
        assertEquals(0, monitor.activeSession?.activeSubagentCount)
    }

    @Test
    fun `should stop only the session that stopped`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.USER_PROMPT_SUBMIT))
        monitor.processEvent(makeEvent(sessionId = "other", eventName = EventName.STOP))

        assertEquals(Session.Phase.ACTIVE, session("session-1", monitor)?.phase)
        assertEquals(Session.Phase.STOPPED, session("other", monitor)?.phase)
    }

    @Test
    fun `should bring a stopped session back to active when the person sends a prompt`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.STOP))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))

        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
    }

    @Test
    fun `should keep the session stopped when the person prompts another session`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(sessionId = "session-1", eventName = EventName.STOP))
        monitor.processEvent(makeEvent(sessionId = "other", eventName = EventName.USER_PROMPT_SUBMIT))

        assertEquals(Session.Phase.STOPPED, session("session-1", monitor)?.phase)
    }

    // Recent sessions

    @Test
    fun `should list the most recent session first`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId = "s1", eventName = EventName.SESSION_START, receivedAt = START))
        monitor.processEvent(makeEvent(sessionId = "s1", eventName = EventName.SESSION_END, receivedAt = START + 10))
        monitor.processEvent(makeEvent(sessionId = "s2", eventName = EventName.SESSION_START, receivedAt = START + 20))
        monitor.processEvent(makeEvent(sessionId = "s2", eventName = EventName.SESSION_END, receivedAt = START + 30))

        assertEquals(2, monitor.recentSessions.size)
        assertEquals("s2", monitor.recentSessions[0].id)
        assertEquals("s1", monitor.recentSessions[1].id)
    }

    @Test
    fun `should keep only the latest sessions up to the limit`() {
        val monitor = SessionMonitor(maxRecentSessions = 3)

        for (i in 1..5) {
            val time = START + i * 10
            monitor.processEvent(makeEvent(sessionId = "s$i", eventName = EventName.SESSION_START, receivedAt = time))
            monitor.processEvent(makeEvent(sessionId = "s$i", eventName = EventName.SESSION_END, receivedAt = time + 5))
        }

        assertEquals(3, monitor.recentSessions.size)
        assertEquals("s5", monitor.recentSessions[0].id)
        assertEquals("s4", monitor.recentSessions[1].id)
        assertEquals("s3", monitor.recentSessions[2].id)
    }

    // Complex scenarios

    @Test
    fun `should follow a session through subagents and tasks and keep its task count once it ends`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))
        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)

        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_START))
        assertEquals(Session.Phase.SUBAGENTS_WORKING, monitor.activeSession?.phase)

        monitor.processEvent(makeEvent(eventName = EventName.TASK_COMPLETED))
        assertEquals(1, monitor.activeSession?.completedTaskCount)

        monitor.processEvent(makeEvent(eventName = EventName.SUBAGENT_STOP))
        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)

        monitor.processEvent(makeEvent(eventName = EventName.TASK_COMPLETED))
        assertEquals(2, monitor.activeSession?.completedTaskCount)

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_END))
        assertNull(monitor.activeSession)
        assertEquals(1, monitor.recentSessions.size)
        assertEquals(2, monitor.recentSessions.first().completedTaskCount)
    }

    // Permission prompts

    @Test
    fun `should show the session needs the person, with the prompt, when Claude Code asks for permission`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))

        monitor.processEvent(makeEvent(eventName = EventName.NOTIFICATION, message = "Claude needs your permission to use Bash"))

        assertEquals(Session.Phase.AWAITING_INPUT, monitor.activeSession?.phase)
        assertEquals("Claude needs your permission to use Bash", monitor.activeSession?.pendingPrompt)
    }

    @Test
    fun `should keep the session active when another session asks for permission`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))

        monitor.processEvent(makeEvent(sessionId = "other", eventName = EventName.NOTIFICATION, message = "blocked"))

        assertEquals(Session.Phase.ACTIVE, session("test-session", monitor)?.phase)
        assertNull(session("test-session", monitor)?.pendingPrompt)
    }

    @Test
    fun `should drop the prompt and go back to active when the person answers the session`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.NOTIFICATION, message = "blocked"))

        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))

        assertEquals(Session.Phase.ACTIVE, monitor.activeSession?.phase)
        assertNull(monitor.activeSession?.pendingPrompt)
    }

    // The UI's change signal (MODULAR_DESIGN §5) — Kotlin only

    @Test
    fun `should tell the screen to look again after each event that changes a session`() {
        val monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName = EventName.SESSION_START))
        monitor.processEvent(makeEvent(eventName = EventName.USER_PROMPT_SUBMIT))
        monitor.processEvent(makeEvent(eventName = EventName.SESSION_END))

        assertEquals(3L, monitor.revision.value)
    }

    @Test
    fun `should not tell the screen to look again when nothing changed`() {
        val monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId = "kept", eventName = EventName.SESSION_START, processId = 100))

        monitor.processEvent(makeEvent(sessionId = "never-seen", eventName = EventName.SESSION_END))
        monitor.endSessionsWhoseProcessIsGone(processes(running = setOf(100)), atSeconds = START + 60)

        assertEquals(1L, monitor.revision.value)
    }
}
