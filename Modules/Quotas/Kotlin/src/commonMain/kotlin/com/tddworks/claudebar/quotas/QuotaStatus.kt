package com.tddworks.claudebar.quotas

/**
 * The health of a quota, declared in order of severity.
 * Rich domain model: status is decided by these thresholds, never by a view.
 */
enum class QuotaStatus {
    /** More than 50% left. */
    HEALTHY,
    /** 20–50% left. */
    WARNING,
    /** Under 20% left. */
    CRITICAL,
    /** Nothing left. */
    DEPLETED;

    /** Whether this status needs the person's attention. */
    val needsAttention: Boolean get() = this != HEALTHY

    companion object {
        /** The status for the percentage left. */
        fun from(percentRemaining: Double): QuotaStatus = when {
            percentRemaining <= 0 -> DEPLETED
            percentRemaining < 20 -> CRITICAL
            percentRemaining < 50 -> WARNING
            else -> HEALTHY
        }

        /**
         * A pace-aware status from the projected end-of-period usage
         * (usage% / timeElapsed%): under 70% healthy, 70–90% warning, 90%+ critical.
         * Before 15% of the period has elapsed, once it is over, or with nothing used
         * yet, falls back to used% thresholds. Depleted stays absolute.
         * [burnRateThreshold] is unused; kept for the burn-rate setting.
         */
        @Suppress("UNUSED_PARAMETER")
        fun from(percentRemaining: Double, percentTimeElapsed: Double, burnRateThreshold: Double): QuotaStatus {
            if (percentRemaining <= 0) return DEPLETED
            val percentUsed = 100 - percentRemaining
            if (percentTimeElapsed >= 15 && percentTimeElapsed < 100 && percentUsed > 0) {
                val projected = percentUsed / percentTimeElapsed
                return when {
                    projected < 0.70 -> HEALTHY
                    projected < 0.90 -> WARNING
                    else -> CRITICAL
                }
            }
            return when {
                percentUsed < 70 -> HEALTHY
                percentUsed < 90 -> WARNING
                else -> CRITICAL
            }
        }
    }
}
