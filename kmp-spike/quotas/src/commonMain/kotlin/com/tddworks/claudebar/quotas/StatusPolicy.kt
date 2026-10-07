package com.tddworks.claudebar.quotas

/** HOW STRICT TO BE — the person's one judgement, for the whole app. */
sealed interface StatusPolicy {
    data object Absolute : StatusPolicy
    data class PaceAware(val burnRateThreshold: Double) : StatusPolicy

    companion object {
        fun from(burnRateWarningEnabled: Boolean, burnRateThreshold: Double): StatusPolicy =
            if (burnRateWarningEnabled) PaceAware(burnRateThreshold) else Absolute
    }
}
