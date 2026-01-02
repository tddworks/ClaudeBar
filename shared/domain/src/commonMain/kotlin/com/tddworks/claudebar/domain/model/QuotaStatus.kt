package com.tddworks.claudebar.domain.model

/**
 * Represents the health status of a usage quota.
 * Rich domain model - status is determined by business rules, not UI logic.
 */
enum class QuotaStatus : Comparable<QuotaStatus> {
    /** Quota has remaining capacity (>50%) */
    HEALTHY,
    /** Quota is getting low (20-50%) */
    WARNING,
    /** Quota is almost exhausted (<20%) */
    CRITICAL,
    /** Quota is completely exhausted (0%) */
    DEPLETED;

    /** Whether this status indicates a problem that needs attention */
    val needsAttention: Boolean
        get() = this != HEALTHY

    /** The severity level (higher = more severe) */
    val severity: Int
        get() = ordinal

    companion object {
        /**
         * Creates a status based on the percentage remaining.
         * This encapsulates the business rules for status thresholds.
         */
        fun from(percentRemaining: Double): QuotaStatus = when {
            percentRemaining <= 0 -> DEPLETED
            percentRemaining < 20 -> CRITICAL
            percentRemaining < 50 -> WARNING
            else -> HEALTHY
        }
    }
}
