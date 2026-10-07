package com.tddworks.claudebar.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val NOW = 1_700_000_000.0

/** Swift's ClaudeSessionTests. */
class SessionTest {
    private fun session(cwd: String = "/tmp", phase: Session.Phase = Session.Phase.ACTIVE, startedAt: Double = NOW) =
        Session(id = "test", cwd = cwd, startedAtSeconds = startedAt, phase = phase)

    @Test
    fun `should be active with no agents or finished tasks when the session starts`() {
        val session = session()

        assertEquals(Session.Phase.ACTIVE, session.phase)
        assertEquals(0, session.activeSubagentCount)
        assertEquals(0, session.completedTaskCount)
        assertTrue(session.isActive)
        assertNull(session.endedAtSeconds)
    }

    @Test
    fun `should be idle, with nothing finished, when opened at its prompt`() {
        val session = session(phase = Session.Phase.STOPPED)

        assertEquals(Session.Phase.STOPPED, session.phase)
        assertNull(session.finishedAtSeconds)
        assertTrue(session.isActive)
        assertEquals(0, session.activeSubagentCount)
        assertEquals(0, session.completedTaskCount)
        assertNull(session.endedAtSeconds)
    }

    @Test
    fun `should show agents working when a subagent starts`() {
        val session = session().subagentStarted()

        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
        assertEquals(1, session.activeSubagentCount)
    }

    @Test
    fun `should count three agents working when three subagents start`() {
        val session = session().subagentStarted().subagentStarted().subagentStarted()

        assertEquals(3, session.activeSubagentCount)
        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
    }

    @Test
    fun `should go back to active when the last subagent stops`() {
        val session = session().subagentStarted().subagentStopped()

        assertEquals(0, session.activeSubagentCount)
        assertEquals(Session.Phase.ACTIVE, session.phase)
    }

    @Test
    fun `should keep showing agents working while a subagent is still running`() {
        val session = session().subagentStarted().subagentStarted().subagentStopped()

        assertEquals(1, session.activeSubagentCount)
        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
    }

    @Test
    fun `should count no agents, never fewer, when more subagents stop than started`() {
        val session = session().subagentStopped().subagentStopped()

        assertEquals(0, session.activeSubagentCount)
        assertEquals(Session.Phase.ACTIVE, session.phase)
    }

    @Test
    fun `should stay stopped when a subagent reports stopping after Claude stopped`() {
        // Claude Code reports a subagent's stop a moment after the turn's own Stop; that must
        // not make an idle session look like it is working.
        val stoppedAt = NOW + 5
        val session = session().subagentStarted().stop(stoppedAt).subagentStopped()

        assertEquals(Session.Phase.STOPPED, session.phase)
        assertEquals(stoppedAt, session.stoppedAtSeconds)
        assertEquals(0, session.activeSubagentCount)
    }

    @Test
    fun `should keep needing the person, with the prompt, when a subagent stops`() {
        val session = session().subagentStarted().awaitInput("Claude needs your permission to use Bash").subagentStopped()

        assertEquals(Session.Phase.AWAITING_INPUT, session.phase)
        assertEquals("Claude needs your permission to use Bash", session.pendingPrompt)
    }

    @Test
    fun `should count each finished task`() {
        val session = session().taskCompleted().taskCompleted().taskCompleted()

        assertEquals(3, session.completedTaskCount)
    }

    @Test
    fun `should show the session stopped with no agents, yet not ended, when Claude stops`() {
        val session = session().subagentStarted().subagentStarted().stop(NOW)

        assertEquals(Session.Phase.STOPPED, session.phase)
        assertEquals(0, session.activeSubagentCount)
        assertTrue(session.isActive) // stopped but not ended
    }

    @Test
    fun `should show the session ended with its end time when it ends`() {
        val endDate = NOW + 10
        val session = session().end(endDate)

        assertEquals(Session.Phase.ENDED, session.phase)
        assertFalse(session.isActive)
        assertEquals(endDate, session.endedAtSeconds)
        assertEquals(0, session.activeSubagentCount)
    }

    @Test
    fun `should print a 45-second session as 45s`() {
        val session = session(startedAt = NOW).end(NOW + 45)

        assertEquals("45s", session.durationDescription(nowSeconds = NOW + 1_000))
    }

    @Test
    fun `should print a session of just over two minutes as 2m 5s`() {
        val session = session(startedAt = NOW).end(NOW + 125)

        assertEquals("2m 5s", session.durationDescription(nowSeconds = NOW + 1_000))
    }

    @Test
    fun `should print a session of just over an hour as 1h 1m`() {
        val session = session(startedAt = NOW).end(NOW + 3660)

        assertEquals("1h 1m", session.durationDescription(nowSeconds = NOW + 10_000))
    }

    @Test
    fun `should be known by its id wherever it runs`() {
        val session1 = Session(id = "abc", cwd = "/tmp", startedAtSeconds = NOW)
        val session2 = Session(id = "abc", cwd = "/other", startedAtSeconds = NOW)

        assertEquals(session1.id, session2.id)
    }

    // Phase guards

    @Test
    fun `should show agents working again when a subagent starts after Claude stopped`() {
        val session = session().stop(NOW).subagentStarted()

        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
        assertEquals(1, session.activeSubagentCount)
    }

    @Test
    fun `should go back to active when the person resumes a stopped session`() {
        val session = session().stop(NOW).resume()

        assertEquals(Session.Phase.ACTIVE, session.phase)
        assertEquals(0, session.activeSubagentCount)
    }

    @Test
    fun `should keep showing agents working when the session resumes with a subagent running`() {
        val session = session().subagentStarted().resume()

        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
        assertEquals(1, session.activeSubagentCount)
    }

    @Test
    fun `should stay ended when an ended session is resumed`() {
        val session = session().end(NOW).resume()

        assertEquals(Session.Phase.ENDED, session.phase)
    }

    @Test
    fun `should stay ended with no agents when a subagent stops after the session ended`() {
        val session = session().subagentStarted().end(NOW).subagentStopped()

        assertEquals(Session.Phase.ENDED, session.phase)
        assertEquals(0, session.activeSubagentCount)
    }

    @Test
    fun `should still count a task finished after Claude stopped`() {
        val session = session().stop(NOW).taskCompleted()

        assertEquals(1, session.completedTaskCount)
    }

    @Test
    fun `should not count a task finished after the session ended`() {
        val session = session().end(NOW).taskCompleted()

        assertEquals(0, session.completedTaskCount)
    }

    @Test
    fun `should stay ended when Claude stops after the session ended`() {
        val session = session().end(NOW).stop(NOW)

        assertEquals(Session.Phase.ENDED, session.phase)
    }

    // Awaiting input

    @Test
    fun `should show the session needs the person, with the prompt, when Claude asks for input`() {
        val session = session().awaitInput("Bash · rm -rf build/")

        assertEquals(Session.Phase.AWAITING_INPUT, session.phase)
        assertEquals("Bash · rm -rf build/", session.pendingPrompt)
    }

    @Test
    fun `should stay ended with no prompt when Claude asks for input after the session ended`() {
        val session = session().end(NOW).awaitInput("Bash · ls")

        assertEquals(Session.Phase.ENDED, session.phase)
        assertNull(session.pendingPrompt)
    }

    @Test
    fun `should drop the prompt and go back to active when the person answers`() {
        val session = session().awaitInput("Bash · ls").resume()

        assertEquals(Session.Phase.ACTIVE, session.phase)
        assertNull(session.pendingPrompt)
    }

    @Test
    fun `should drop the prompt and show agents working when a subagent starts`() {
        val session = session().awaitInput("Bash · ls").subagentStarted()

        assertEquals(Session.Phase.SUBAGENTS_WORKING, session.phase)
        assertNull(session.pendingPrompt)
    }

    // Finishing

    @Test
    fun `should remember when Claude stopped as the time the session finished`() {
        val session = session().stop(NOW)

        assertEquals(NOW, session.stoppedAtSeconds)
        assertEquals(NOW, session.finishedAtSeconds)
    }

    @Test
    fun `should have no finish time while the session runs`() {
        assertNull(session().finishedAtSeconds)
    }

    @Test
    fun `should take the end time over the stop time as the time the session finished`() {
        val ended = NOW + 30
        val session = session().stop(NOW).end(ended)

        assertEquals(ended, session.finishedAtSeconds)
    }

    @Test
    fun `should forget the stop time when a stopped session resumes`() {
        val session = session().stop(NOW).resume()

        assertNull(session.stoppedAtSeconds)
        assertNull(session.finishedAtSeconds)
    }

    // Identity

    @Test
    fun `should name the session after the folder it runs in`() {
        assertEquals("claudebar", session(cwd = "/Users/me/github/tddworks/claudebar").repoName)
    }

    @Test
    fun `should name the session after its folder even when the path ends in a slash`() {
        assertEquals("claudebar", session(cwd = "/Users/me/github/claudebar/").repoName)
    }

    @Test
    fun `should print each phase with the notch's words — Working, Agents working, Needs you, Done or Ended`() {
        assertEquals("Working", Session.Phase.ACTIVE.label)
        assertEquals("Agents working", Session.Phase.SUBAGENTS_WORKING.label)
        assertEquals("Needs you", Session.Phase.AWAITING_INPUT.label)
        assertEquals("Done", Session.Phase.STOPPED.label)
        assertEquals("Ended", Session.Phase.ENDED.label)
    }
}
