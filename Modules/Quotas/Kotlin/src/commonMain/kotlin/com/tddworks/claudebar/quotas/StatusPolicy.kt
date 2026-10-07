package com.tddworks.claudebar.quotas

/**
 * HOW STRICT TO BE — the person's one judgement, for the whole app
 * (Settings → General → burn-rate warning). Every surface reads a quota's status under it.
 * Depleted at 0 and critical under 20% are absolute whatever the policy.
 */
sealed class StatusPolicy {
    /** Warning under 50% left, whatever the pace. */
    data object Absolute : StatusPolicy()

    /** Warning only while burning faster than the sustainable pace; no window falls back to absolute. */
    data class PaceAware(val burnRateThreshold: Double) : StatusPolicy()

    companion object {
        /** The policy the burn-rate settings describe. */
        fun from(burnRateWarningEnabled: Boolean, burnRateThreshold: Double): StatusPolicy =
            if (burnRateWarningEnabled) PaceAware(burnRateThreshold) else Absolute
    }
}
