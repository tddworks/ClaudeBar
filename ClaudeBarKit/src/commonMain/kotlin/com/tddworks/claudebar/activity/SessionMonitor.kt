package com.tddworks.claudebar.activity

import kotlin.native.ObjCName

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * The one source of truth for Claude Code sessions, fed by hook events.
 *
 * Several sessions run at once (one per terminal), each tracked on its own. A session is
 * picked up from whichever of its events arrives first, not only `SessionStart`: one already
 * running when ClaudeBar launched sent that before anything listened.
 *
 * Safe from any thread; [revision] moves after every change, for the UI to re-read
 * (MODULAR_DESIGN §5).
 */
public class SessionMonitor internal constructor(private val maxRecentSessions: Int = 10) {
    private val lock = SynchronizedObject()
    private var running: List<Session> = emptyList()
    private var recent: List<Session> = emptyList()

    /** When each running session last sent an event, by session ID. */
    private val lastEventAt = mutableMapOf<String, Double>()

    private val changes = MutableStateFlow(0L)

    /** Bumped after every change to the sessions. */
    val revision: StateFlow<Long> = changes.asStateFlow()

    /** Every running session, in the order first seen. */
    @ObjCName("sessionsUntracked")
    val sessions: List<Session> get() = synchronized(lock) { running }

    /** Ended sessions, most recent first. */
    @ObjCName("recentSessionsUntracked")
    val recentSessions: List<Session> get() = synchronized(lock) { recent }

    internal fun processEvent(event: SessionEvent) {
        val changed = synchronized(lock) {
            if (event.eventName == SessionEvent.EventName.SESSION_END) {
                return@synchronized endSession(event.sessionId, event.receivedAtSeconds)
            }
            val index = indexOfSession(event)
            lastEventAt[event.sessionId] = event.receivedAtSeconds
            var session = running[index]
            if (event.processId != null && session.processId == null) session = session.runsInProcess(event.processId)
            session = when (event.eventName) {
                // A new session idles at its prompt until the first one; a known one is being
                // resumed or compacted (mid-turn) and keeps its phase and progress.
                SessionEvent.EventName.SESSION_START, SessionEvent.EventName.SESSION_END -> session
                SessionEvent.EventName.TASK_COMPLETED -> session.taskCompleted()
                SessionEvent.EventName.SUBAGENT_START -> session.subagentStarted()
                SessionEvent.EventName.SUBAGENT_STOP -> session.subagentStopped()
                SessionEvent.EventName.STOP, SessionEvent.EventName.STOP_FAILURE -> session.stop(event.receivedAtSeconds)
                SessionEvent.EventName.USER_PROMPT_SUBMIT -> session.resume()
                SessionEvent.EventName.NOTIFICATION -> session.awaitInput(event.message)
            }
            running = running.toMutableList().also { it[index] = session }
            true
        }
        if (changed) changes.update { it + 1 }
    }

    /**
     * Ends every session whose Claude Code process is gone: killed without `SessionEnd`,
     * nothing else would end it. A session that never said its process is left alone.
     */
    internal fun endSessionsWhoseProcessIsGone(liveness: ProcessLiveness, atSeconds: Double) {
        val gone = sessions.filter { session -> session.processId?.let { !liveness.isRunning(it) } ?: false }
        if (gone.isEmpty()) return
        val changed = synchronized(lock) { gone.map { endSession(it.id, atSeconds) }.any { it } }
        if (changed) changes.update { it + 1 }
    }

    /**
     * Every running session, the one that most needs the person first: blocked, then agents
     * working, then working alone, then stopped; among equals, the one heard from last.
     */
    @ObjCName("sessionsByProminenceUntracked")
    val sessionsByProminence: List<Session>
        get() = synchronized(lock) {
            running.sortedWith(
                compareByDescending<Session> { prominence(it.phase) }
                    .thenByDescending { lastEventAt[it.id] ?: it.startedAtSeconds },
            )
        }

    /** The one session for where a single status fits (the menu bar glyph); null when none runs. */
    @ObjCName("activeSessionUntracked")
    val activeSession: Session? get() = sessionsByProminence.firstOrNull()

    @ObjCName("hasActiveSessionUntracked")
    val hasActiveSession: Boolean get() = sessions.isNotEmpty()

    private fun prominence(phase: Session.Phase): Int = when (phase) {
        Session.Phase.AWAITING_INPUT -> 3
        Session.Phase.SUBAGENTS_WORKING -> 2
        Session.Phase.ACTIVE -> 1
        Session.Phase.STOPPED, Session.Phase.ENDED -> 0
    }

    /**
     * The event's session, added on its first event. One just started idles at its prompt.
     * One picked up mid-flight starts stopped too unless the event shows a turn underway —
     * a late `SubagentStop` or `TaskCompleted` doesn't, and "Working" would stick until the
     * next prompt — and its start is when ClaudeBar first heard from it.
     */
    private fun indexOfSession(event: SessionEvent): Int {
        val known = running.indexOfFirst { it.id == event.sessionId }
        if (known >= 0) return known
        var session = Session(
            id = event.sessionId,
            cwd = event.cwd,
            startedAtSeconds = event.receivedAtSeconds,
            processId = event.processId,
            phase = if (event.eventName == SessionEvent.EventName.SESSION_START) Session.Phase.STOPPED else Session.Phase.ACTIVE,
        )
        when (event.eventName) {
            SessionEvent.EventName.SESSION_START, SessionEvent.EventName.USER_PROMPT_SUBMIT,
            SessionEvent.EventName.SUBAGENT_START, SessionEvent.EventName.NOTIFICATION -> Unit
            SessionEvent.EventName.SUBAGENT_STOP, SessionEvent.EventName.TASK_COMPLETED,
            SessionEvent.EventName.STOP, SessionEvent.EventName.STOP_FAILURE,
            SessionEvent.EventName.SESSION_END -> session = session.stop(event.receivedAtSeconds)
        }
        running = running + session
        return running.size - 1
    }

    /** Under [lock]; true when a session ended. */
    private fun endSession(id: String, atSeconds: Double): Boolean {
        val session = running.firstOrNull { it.id == id } ?: return false
        running = running.filterNot { it.id == id }
        lastEventAt.remove(id)
        recent = (listOf(session.end(atSeconds)) + recent).take(maxRecentSessions)
        return true
    }
}
