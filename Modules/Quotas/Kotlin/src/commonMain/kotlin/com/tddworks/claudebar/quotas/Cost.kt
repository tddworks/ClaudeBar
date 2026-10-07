package com.tddworks.claudebar.quotas

import kotlin.native.ObjCName

/** The judgement on a cost against its budget: ON TRACK · NEAR LIMIT · OVER BUDGET. */
enum class BudgetStatus {
    /** Under 80% of the budget. */
    WITHIN_BUDGET,
    /** 80–100% of the budget. */
    APPROACHING_LIMIT,
    /** Over the budget. */
    OVER_BUDGET;

    val badgeText: String
        get() = when (this) {
            WITHIN_BUDGET -> "ON TRACK"
            APPROACHING_LIMIT -> "NEAR LIMIT"
            OVER_BUDGET -> "OVER BUDGET"
        }

    val needsAttention: Boolean get() = this != WITHIN_BUDGET

    companion object {
        /** The status of a cost against a budget; no budget is always within it. */
        fun from(costNanos: Long, budgetNanos: Long): BudgetStatus {
            if (budgetNanos <= 0) return WITHIN_BUDGET
            return when {
                costNanos >= budgetNanos -> OVER_BUDGET
                costNanos * 5 >= budgetNanos * 4 -> APPROACHING_LIMIT
                else -> WITHIN_BUDGET
            }
        }
    }
}

/** One part of a cost — a model's share of the day's spend. */
data class CostLine(
    val label: String,
    val amountNanos: Long,
    /** What it was spent on, as the vendor counts it ("1.2M tokens · 40 calls"). */
    val detail: String?,
)

/**
 * Money gone over a period: API spend, or a subscription's extra usage against its budget.
 * Interim shape (CANONICAL_MODEL): becomes `Cost`, judged by a `Budget`, never shown as a quota.
 */
data class CostUsage(
    val totalCostNanos: Long,
    /** The built-in budget (Pro extra usage, e.g. $20); null for API accounts. */
    val budgetNanos: Long?,
    /** Seconds spent on API calls. */
    val apiDuration: Double,
    /** Wall-clock seconds, including thinking and typing. */
    val wallDuration: Double,
    @ObjCName("linesAdded64") val linesAdded: Long,
    @ObjCName("linesRemoved64") val linesRemoved: Long,
    val providerId: String,
    val kind: Kind,
    val capturedAtSeconds: Double,
    val resetsAtSeconds: Double?,
    /** "Resets Jan 1, 2026". */
    val resetText: String?,
    /** Its parts, largest first; empty when not broken down. */
    val lines: List<CostLine>,
) {
    enum class Kind { API_COST, EXTRA_USAGE }

    /** The status against a budget the person set. */
    fun budgetStatus(budgetNanos: Long): BudgetStatus = BudgetStatus.from(totalCostNanos, budgetNanos)

    /** The status against the built-in budget, if there is one. */
    val budgetStatusFromBuiltIn: BudgetStatus? get() = budgetNanos?.let { BudgetStatus.from(totalCostNanos, it) }

    /** The share of a budget spent, as a percentage; 0 without a budget. */
    fun budgetPercentUsed(budgetNanos: Long): Double =
        if (budgetNanos <= 0) 0.0 else totalCostNanos * 100.0 / budgetNanos

    /** The unspent built-in budget, never below zero. */
    val budgetRemainingNanos: Long? get() = budgetNanos?.let { maxOf(0L, it - totalCostNanos) }
}
