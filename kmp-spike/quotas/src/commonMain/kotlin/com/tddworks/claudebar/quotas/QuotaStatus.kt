package com.tddworks.claudebar.quotas

/** The health of a quota — a port of Modules/Quotas/Sources/QuotaStatus.swift. Declared in order of severity. */
enum class QuotaStatus {
    HEALTHY, WARNING, CRITICAL, DEPLETED;

    val needsAttention: Boolean get() = this != HEALTHY

    companion object {
        fun from(percentRemaining: Double): QuotaStatus = when {
            percentRemaining <= 0 -> DEPLETED
            percentRemaining < 20 -> CRITICAL
            percentRemaining < 50 -> WARNING
            else -> HEALTHY
        }

        /** Pace-aware: projects end-of-period usage once 15% of the window has elapsed. */
        fun from(percentRemaining: Double, percentTimeElapsed: Double): QuotaStatus {
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
