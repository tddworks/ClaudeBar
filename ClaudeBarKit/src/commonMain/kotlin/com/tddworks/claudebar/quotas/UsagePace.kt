package com.tddworks.claudebar.quotas

import kotlin.math.abs

/** The pace of consumption against the clock. */
enum class UsagePace {
    /** Within 5 points of the clock. */
    ON_PACE,
    /** Consuming faster than the clock: may run out early. */
    AHEAD,
    /** Consuming slower than the clock: room to spare. */
    BEHIND,
    /** No window to be on pace in. */
    UNKNOWN;

    val displayName: String
        get() = when (this) {
            ON_PACE -> "On track"
            AHEAD -> "Running hot"
            BEHIND -> "Room to spare"
            UNKNOWN -> "Unknown"
        }

    companion object {
        private const val ON_PACE_THRESHOLD = 5.0

        fun from(percentUsed: Double, percentTimeElapsed: Double): UsagePace {
            val difference = percentUsed - percentTimeElapsed
            return when {
                abs(difference) <= ON_PACE_THRESHOLD -> ON_PACE
                difference > 0 -> AHEAD
                else -> BEHIND
            }
        }
    }
}

/**
 * Six-level urgency for the expected-pace tick, graded by the projected end-of-period
 * usage. Separate from [QuotaStatus], which colors the bar itself.
 */
enum class PaceLevel {
    /** Projected under 50%. */
    COMFORTABLE,
    /** Projected 50–75%. */
    ON_TRACK,
    /** Projected 75–90%. */
    WARMING,
    /** Projected 90–100%. */
    PRESSING,
    /** Projected 100–120%. */
    CRITICAL,
    /** Projected 120%+. */
    RUNAWAY;

    companion object {
        /** The level, or null before 3% of the period has elapsed or once it is over. */
        fun from(percentUsed: Double, percentTimeElapsed: Double): PaceLevel? {
            if (percentTimeElapsed < 3 || percentTimeElapsed >= 100) return null
            if (percentUsed <= 0) return COMFORTABLE
            val projected = percentUsed / percentTimeElapsed
            return when {
                projected < 0.50 -> COMFORTABLE
                projected < 0.75 -> ON_TRACK
                projected < 0.90 -> WARMING
                projected < 1.00 -> PRESSING
                projected < 1.20 -> CRITICAL
                else -> RUNAWAY
            }
        }
    }
}
