package com.tddworks.claudebar.activity

/**
 * A running or recent Claude Code session: its phase, its subagents and finished tasks.
 * A value: each change returns the session as it is afterwards.
 *
 * Swift's `ClaudeSession`; the Kotlin name drops the vendor (ArchitectureTest), and the
 * canonical model calls it Activity's *Session*.
 */
internal data class Session(
    val id: String,
    val cwd: String,
    val startedAtSeconds: Double,
    /** The Claude Code process running it, once a hook event has said. */
    val processId: Int? = null,
    /**
     * `ACTIVE` for a session seen mid-turn; `STOPPED` for one just opened at its prompt —
     * idle, with nothing finished yet, so [finishedAtSeconds] stays null and the notch has
     * nothing to flash.
     */
    val phase: Phase = Phase.ACTIVE,
    val activeSubagentCount: Int = 0,
    val completedTaskCount: Int = 0,
    val endedAtSeconds: Double? = null,
    /**
     * When the current turn stopped; cleared when work resumes. Not [endedAtSeconds]: a
     * stopped session is alive and revives on the next `UserPromptSubmit`.
     */
    val stoppedAtSeconds: Double? = null,
    /** What Claude Code is blocked on while `AWAITING_INPUT`; cleared when work resumes. */
    val pendingPrompt: String? = null,
) {
    enum class Phase(
        /** The notch's words for the same states (docs/features/notch), so the two never disagree. */
        val label: String,
    ) {
        ACTIVE("Working"),
        SUBAGENTS_WORKING("Agents working"),
        /** Blocked on the person, typically a permission prompt. */
        AWAITING_INPUT("Needs you"),
        STOPPED("Done"),
        ENDED("Ended"),
    }

    /** Records which process runs this session, when a later event says. */
    fun runsInProcess(processId: Int): Session = copy(processId = processId)

    /** A subagent started. It also revives a stopped session: a new turn is clearly underway. */
    fun subagentStarted(): Session =
        if (phase == Phase.ENDED) this else copy(activeSubagentCount = activeSubagentCount + 1).withWorkPhase()

    /**
     * A subagent stopped. Changes the phase only while agents defined it: Claude Code reports
     * a subagent's stop just after the turn's own `Stop`, which must not revive a stopped
     * session or release one waiting on the person.
     */
    fun subagentStopped(): Session {
        if (phase == Phase.ENDED) return this
        val fewer = copy(activeSubagentCount = maxOf(0, activeSubagentCount - 1))
        return if (phase == Phase.SUBAGENTS_WORKING) fewer.withWorkPhase() else fewer
    }

    /** A new turn began (`UserPromptSubmit`); without it `Stop` would leave the session stopped for good. */
    fun resume(): Session = if (phase == Phase.ENDED) this else withWorkPhase()

    /** Claude Code is blocked waiting on the person, on [prompt]. */
    fun awaitInput(prompt: String? = null): Session =
        if (phase == Phase.ENDED) this
        else copy(phase = Phase.AWAITING_INPUT, pendingPrompt = prompt, stoppedAtSeconds = null)

    fun taskCompleted(): Session =
        if (phase == Phase.ENDED) this else copy(completedTaskCount = completedTaskCount + 1)

    /** The turn stopped; the session lives on. */
    fun stop(atSeconds: Double): Session =
        if (phase == Phase.ENDED) this
        else copy(phase = Phase.STOPPED, activeSubagentCount = 0, stoppedAtSeconds = atSeconds, pendingPrompt = null)

    fun end(atSeconds: Double): Session =
        copy(phase = Phase.ENDED, activeSubagentCount = 0, endedAtSeconds = atSeconds)

    /**
     * When it last finished something — its end, else its last turn's stop; null while
     * working. The notch times its "done" flash on it; the end wins, being for good.
     */
    val finishedAtSeconds: Double? get() = endedAtSeconds ?: stoppedAtSeconds

    /** The folder's name, which is how people refer to a session ("the claudebar one"). */
    val repoName: String get() = lastPathComponent(cwd)

    /** Not ended. */
    val isActive: Boolean get() = phase != Phase.ENDED

    fun durationSeconds(nowSeconds: Double): Double = (endedAtSeconds ?: nowSeconds) - startedAtSeconds

    /** "45s", "2m 5s", "1h 1m". */
    fun durationDescription(nowSeconds: Double): String {
        val total = durationSeconds(nowSeconds).toInt()
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m ${seconds}s"
            else -> "${seconds}s"
        }
    }

    private fun withWorkPhase(): Session = copy(
        pendingPrompt = null,
        stoppedAtSeconds = null,
        phase = if (activeSubagentCount > 0) Phase.SUBAGENTS_WORKING else Phase.ACTIVE,
    )
}
