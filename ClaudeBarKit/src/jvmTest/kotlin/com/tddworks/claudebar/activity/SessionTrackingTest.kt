package com.tddworks.claudebar.activity

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The hook loop, as the app ran it: events in, sessions tracked, a session's start and end announced. */
@OptIn(ExperimentalCoroutinesApi::class)
class SessionTrackingTest {
    private class Hooks : HookEventReceiver {
        val events = Channel<SessionEvent>(Channel.UNLIMITED)
        var stopped = false
        override suspend fun start(): Flow<SessionEvent> = events.consumeAsFlow()
        override suspend fun stop() { stopped = true; events.close() }
    }

    private class Announcements : SessionAnnouncer {
        val said = mutableListOf<String>()
        override suspend fun announce(title: String, body: String, category: String) { said += "$category|$title|$body" }
    }

    private fun event(name: SessionEvent.EventName, id: String = "s1", cwd: String = "/code/claudebar", at: Double = 1_000.0, pid: Int? = null) =
        SessionEvent(id, name, cwd, at, processId = pid)

    private fun TestScope.tracking(hooks: Hooks, said: Announcements, alive: Set<Int> = emptySet(), now: Double = 2_000.0) =
        SessionTracking(SessionMonitor(), hooks, { it in alive }, said, { now }, CoroutineScopeOf(this))

    @Test
    fun `should track a session from the hook events it sends`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val tracking = tracking(hooks, Announcements())
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.SESSION_START)); runCurrent()
        assertEquals(listOf("s1"), tracking.sessions.sessions.map { it.id })
        tracking.stop()
    }

    @Test
    fun `should ignore ClaudeBar's own probe sessions`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val said = Announcements(); val tracking = tracking(hooks, said)
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.SESSION_START, cwd = "/Users/me/Library/Application Support/ClaudeBar/Probe")); runCurrent()
        assertTrue(tracking.sessions.sessions.isEmpty())
        assertTrue(said.said.isEmpty())
        tracking.stop()
    }

    @Test
    fun `should announce a session starting in its project`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val said = Announcements(); val tracking = tracking(hooks, said)
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.SESSION_START)); runCurrent()
        assertEquals(listOf("SESSION_START|Claude Code Started|Session started in claudebar"), said.said)
        tracking.stop()
    }

    @Test
    fun `should announce a session ending with the tasks it completed and how long it took`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val said = Announcements(); val tracking = tracking(hooks, said)
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.USER_PROMPT_SUBMIT, at = 1_000.0)); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.TASK_COMPLETED, at = 1_010.0)); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.SESSION_END, at = 1_125.0)); runCurrent()
        assertEquals("SESSION_END|Claude Code Finished|claudebar — Completed 1 task in 2m 5s", said.said.last())
        tracking.stop()
    }

    @Test
    fun `should say only that a session ended when it never saw it run`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val said = Announcements(); val tracking = tracking(hooks, said)
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.SESSION_END)); runCurrent()
        assertEquals(listOf("SESSION_END|Claude Code Finished|claudebar — Session ended"), said.said)
        tracking.stop()
    }

    @Test
    fun `should end a session whose process is gone at the next sweep`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val tracking = tracking(hooks, Announcements(), alive = emptySet())
        tracking.start(); runCurrent()
        hooks.events.send(event(SessionEvent.EventName.USER_PROMPT_SUBMIT, pid = 42)); runCurrent()
        assertEquals(1, tracking.sessions.sessions.size)
        advanceTimeBy(SessionTracking.SWEEP_SECONDS.toLong() * 1000 + 1); runCurrent()
        assertTrue(tracking.sessions.sessions.isEmpty())
        tracking.stop()
    }

    @Test
    fun `should stop listening when stopped`() = runTest(StandardTestDispatcher()) {
        val hooks = Hooks(); val tracking = tracking(hooks, Announcements())
        tracking.start(); runCurrent()
        tracking.stop(); runCurrent()
        assertTrue(hooks.stopped)
    }
}

/** The test's scheduler as the tracking's scope, so virtual time drives the sweep. */
private fun CoroutineScopeOf(test: TestScope) = kotlinx.coroutines.CoroutineScope(test.coroutineContext + kotlinx.coroutines.Job())
