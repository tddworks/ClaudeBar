package com.tddworks.claudebar.domain.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Represents cost-based usage data for Claude accounts.
 * Used for API accounts (pay-per-use) and Pro accounts with Extra usage enabled.
 */
data class CostUsage(
    /** The total cost/spent amount in dollars */
    val totalCost: Double,

    /** The budget limit (for Pro accounts with Extra usage, e.g., $20.00) */
    val budget: Double? = null,

    /** Total time spent on API calls */
    val apiDuration: Duration,

    /** Total wall clock time (includes thinking/typing time) */
    val wallDuration: Duration = Duration.ZERO,

    /** Number of lines of code added */
    val linesAdded: Int = 0,

    /** Number of lines of code removed */
    val linesRemoved: Int = 0,

    /** The provider ID this cost belongs to (e.g., "claude") */
    val providerId: String,

    /** When this usage data was captured */
    val capturedAt: Instant = Clock.System.now(),

    /** When this cost usage resets (for Pro Extra usage) */
    val resetsAt: Instant? = null,

    /** Human-readable reset text (e.g., "Resets Jan 1, 2026") */
    val resetText: String? = null
) {
    /** Formatted cost string (e.g., "$0.55") */
    val formattedCost: String
        get() = "$${formatDecimal(totalCost, 2)}"

    /** Formatted API duration (e.g., "6m 19.7s") */
    val formattedApiDuration: String
        get() = formatDuration(apiDuration)

    /** Formatted wall duration (e.g., "6h 33m 10.2s") */
    val formattedWallDuration: String
        get() = formatDuration(wallDuration)

    /** Formatted code changes (e.g., "+10 / -5 lines") */
    val formattedCodeChanges: String
        get() = "+$linesAdded / -$linesRemoved lines"

    /** Calculates the budget status based on the given budget threshold */
    fun budgetStatus(budget: Double): BudgetStatus =
        BudgetStatus.from(totalCost, budget)

    /** Calculates budget status using the built-in budget (for Pro Extra usage) */
    val budgetStatusFromBuiltIn: BudgetStatus?
        get() = budget?.let { BudgetStatus.from(totalCost, it) }

    /** Calculates the percentage of budget used */
    fun budgetPercentUsed(budget: Double): Double {
        if (budget <= 0) return 0.0
        return (totalCost / budget) * 100
    }

    /** Calculates percentage used from built-in budget (for Pro Extra usage) */
    val budgetPercentUsedFromBuiltIn: Double?
        get() = budget?.let { budgetPercentUsed(it) }

    /** Formatted budget string (e.g., "$20.00") */
    val formattedBudget: String?
        get() = budget?.let { "$${formatDecimal(it, 2)}" }

    private fun formatDuration(duration: Duration): String {
        val totalSeconds = duration.inWholeSeconds
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = duration.inWholeMilliseconds / 1000.0 % 60

        return when {
            hours > 0 -> "${hours}h ${minutes}m ${formatDecimal(seconds, 1)}s"
            minutes > 0 -> "${minutes}m ${formatDecimal(seconds, 1)}s"
            else -> "${formatDecimal(seconds, 1)}s"
        }
    }

    companion object {
        /**
         * Cross-platform decimal formatting (replaces String.format)
         */
        private fun formatDecimal(value: Double, decimals: Int): String {
            // Manual power calculation for cross-platform support
            var factor = 1.0
            repeat(decimals) { factor *= 10.0 }
            val rounded = kotlin.math.round(value * factor) / factor
            val parts = rounded.toString().split(".")
            val intPart = parts[0]
            val decPart = if (parts.size > 1) parts[1] else ""
            val paddedDecPart = decPart.padEnd(decimals, '0').take(decimals)
            return "$intPart.$paddedDecPart"
        }
    }
}
