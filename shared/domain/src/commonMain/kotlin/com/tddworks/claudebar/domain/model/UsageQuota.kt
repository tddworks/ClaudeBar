package com.tddworks.claudebar.domain.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * Represents a single usage quota measurement for an AI provider.
 * This is a rich domain model that encapsulates quota-related behavior.
 */
data class UsageQuota(
    /** The percentage of quota remaining (0-100) */
    val percentRemaining: Double,

    /** The type of quota (session, weekly, model-specific) */
    val quotaType: QuotaType,

    /** The provider ID this quota belongs to (e.g., "claude", "codex", "gemini") */
    val providerId: String,

    /** When this quota will reset (if known) */
    val resetsAt: Instant? = null,

    /** Raw reset text from CLI (e.g., "Resets 11am", "Resets Jan 15") */
    val resetText: String? = null
) : Comparable<UsageQuota> {

    init {
        require(percentRemaining in 0.0..100.0) {
            "percentRemaining must be between 0 and 100"
        }
    }

    /**
     * The current health status based on percentage remaining.
     * This is a domain rule: status is determined by business thresholds.
     */
    val status: QuotaStatus
        get() = QuotaStatus.from(percentRemaining)

    /** The percentage that has been used (0-100) */
    val percentUsed: Double
        get() = 100 - percentRemaining

    /** Whether this quota is completely exhausted */
    val isDepleted: Boolean
        get() = percentRemaining <= 0

    /** Whether this quota needs attention (warning, critical, or depleted) */
    val needsAttention: Boolean
        get() = status.needsAttention

    /** Time until this quota resets (if known) */
    val timeUntilReset: Duration?
        get() = resetsAt?.let { resetTime ->
            val now = Clock.System.now()
            val diff = resetTime - now
            if (diff.isNegative()) Duration.ZERO else diff
        }

    /** Human-readable description of time until reset */
    val resetDescription: String?
        get() = timeUntilReset?.let { duration ->
            val hours = duration.inWholeHours
            val minutes = (duration.inWholeMinutes % 60).toInt()

            when {
                hours > 24 -> {
                    val days = hours / 24
                    "Resets in ${days}d ${hours % 24}h"
                }
                hours > 0 -> "Resets in ${hours}h ${minutes}m"
                minutes > 0 -> "Resets in ${minutes}m"
                else -> "Resets soon"
            }
        }

    override fun compareTo(other: UsageQuota): Int =
        percentRemaining.compareTo(other.percentRemaining)

    companion object {
        /** Creates a UsageQuota with clamped percentage value */
        fun create(
            percentRemaining: Double,
            quotaType: QuotaType,
            providerId: String,
            resetsAt: Instant? = null,
            resetText: String? = null
        ): UsageQuota = UsageQuota(
            percentRemaining = percentRemaining.coerceIn(0.0, 100.0),
            quotaType = quotaType,
            providerId = providerId,
            resetsAt = resetsAt,
            resetText = resetText
        )
    }
}
