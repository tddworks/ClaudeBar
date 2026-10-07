package com.tddworks.claudebar.activity

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Says something about a session to the person — a notification; the kit fills it from alerting. */
internal fun interface SessionAnnouncer {
    suspend fun announce(title: String, body: String, category: String)
}

/**
 * Follows Claude Code's sessions while hooks are on: listens for hook events, feeds them to
 * [sessions] — ClaudeBar's own probe runs left out (#172) — announces a session starting and
 * ending, and every [SWEEP_SECONDS] ends sessions whose process died without a `SessionEnd`.
 */
internal class SessionTracking(
    val sessions: SessionMonitor,
    private val receiver: HookEventReceiver,
    private val liveness: ProcessLiveness,
    private val announcer: SessionAnnouncer?,
    private val now: () -> Double,
    private val scope: CoroutineScope,
) {
    private var listening: Job? = null
    private var sweeping: Job? = null

    /** Starts listening; a running loop is replaced. */
    fun start() {
        if (listening != null) stop()
        sweeping = scope.launch {
            while (isActive) {
                delay((SWEEP_SECONDS * 1000).toLong())
                sessions.endSessionsWhoseProcessIsGone(liveness, now())
            }
        }
        listening = scope.launch {
            val events = receiver.start()
            AppLog.hooks.info("Hook server started, listening for events")
            events.collect { event ->
                if (event.isClaudeBarProbe) return@collect
                sessions.processEvent(event)
                announce(event)
            }
        }
    }

    /** Stops listening and sweeping; nothing when not started. */
    fun stop() {
        val running = listening ?: return
        sweeping?.cancel()
        sweeping = null
        running.cancel()
        listening = null
        scope.launch { receiver.stop() }
    }

    private suspend fun announce(event: SessionEvent) {
        val announcer = announcer ?: return
        val project = lastPathComponent(event.cwd)
        when (event.eventName) {
            SessionEvent.EventName.SESSION_START ->
                announcer.announce("Claude Code Started", "Session started in $project", "SESSION_START")
            SessionEvent.EventName.SESSION_END -> {
                // The session that just ended, not merely the newest: several can run at once.
                val ended = sessions.recentSessions.firstOrNull { it.id == event.sessionId }
                val summary = if (ended == null) "Session ended" else {
                    val duration = ended.durationDescription(now())
                    val tasks = ended.completedTaskCount
                    if (tasks > 0) "Completed $tasks task${if (tasks == 1) "" else "s"} in $duration"
                    else "Session ended after $duration"
                }
                announcer.announce("Claude Code Finished", "$project — $summary", "SESSION_END")
            }
            else -> Unit
        }
    }

    companion object {
        const val SWEEP_SECONDS = 30.0
    }
}
