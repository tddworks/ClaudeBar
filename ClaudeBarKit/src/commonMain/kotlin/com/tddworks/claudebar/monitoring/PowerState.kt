package com.tddworks.claudebar.monitoring

import kotlinx.coroutines.flow.Flow

/** A sleep/wake transition the background monitoring loop reacts to. */
internal enum class PowerEvent {
    /** The system or display is going to sleep — the loop pauses. */
    WILL_SLEEP,

    /** The system or display woke — the loop resumes and refreshes immediately. */
    DID_WAKE,
}

/**
 * The power state the background loop reads so it doesn't burn power while the person is away
 * (#204): it pauses while the display or system sleeps, refreshes at once on wake, and
 * stretches its cadence on battery. Optional in `QuotaMonitor`: none means the plain timed loop.
 */
internal interface PowerStateProvider {
    /** The display (or the whole system) is asleep — no refresh, no CLI started. */
    val isDisplayAsleep: Boolean

    /** The Mac runs on battery — the loop refreshes less often. */
    val isOnBattery: Boolean

    /**
     * Sleep/wake transitions, to wake the paused loop the moment the Mac comes back. An
     * implementation updates [isDisplayAsleep] before it emits, so a loop that re-reads it after
     * an event sees the new state.
     */
    fun events(): Flow<PowerEvent>
}
