package com.tddworks.claudebar.domain.model

/**
 * Represents the budget status for cost-based tracking.
 * Similar to QuotaStatus but for budget thresholds instead of percentage remaining.
 */
enum class BudgetStatus : Comparable<BudgetStatus> {
    /** Cost is below 80% of budget */
    WITHIN_BUDGET,
    /** Cost is between 80-100% of budget */
    APPROACHING_LIMIT,
    /** Cost exceeds 100% of budget */
    OVER_BUDGET;

    /** Text to display on status badges */
    val badgeText: String
        get() = when (this) {
            WITHIN_BUDGET -> "ON TRACK"
            APPROACHING_LIMIT -> "NEAR LIMIT"
            OVER_BUDGET -> "OVER BUDGET"
        }

    /** Whether this status requires user attention */
    val needsAttention: Boolean
        get() = this != WITHIN_BUDGET

    /** Severity level for comparison (higher = worse) */
    val severity: Int
        get() = ordinal

    companion object {
        /**
         * Determines budget status based on current cost and budget threshold.
         */
        fun from(cost: Double, budget: Double): BudgetStatus {
            if (budget <= 0) return WITHIN_BUDGET

            val percentUsed = (cost / budget) * 100

            return when {
                percentUsed >= 100 -> OVER_BUDGET
                percentUsed >= 80 -> APPROACHING_LIMIT
                else -> WITHIN_BUDGET
            }
        }
    }
}
