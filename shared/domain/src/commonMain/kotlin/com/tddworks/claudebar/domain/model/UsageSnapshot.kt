package com.tddworks.claudebar.domain.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

/**
 * Represents a point-in-time snapshot of usage quotas for an AI provider.
 * This is an aggregate root that collects all quota information for a provider.
 */
data class UsageSnapshot(
    /** The provider ID this snapshot belongs to (e.g., "claude", "codex", "gemini") */
    val providerId: String,

    /** All quotas captured in this snapshot (empty for API accounts) */
    val quotas: List<UsageQuota>,

    /** When this snapshot was captured */
    val capturedAt: Instant,

    /** Optional account information */
    val accountEmail: String? = null,
    val accountOrganization: String? = null,
    val loginMethod: String? = null,

    /** The account tier (e.g., Claude Max, Pro, or custom tier from other providers) */
    val accountTier: AccountTier? = null,

    /** Cost-based usage data (for Claude API accounts) */
    val costUsage: CostUsage? = null
) {
    /** Finds a specific quota type from this snapshot */
    fun quota(type: QuotaType): UsageQuota? =
        quotas.find { it.quotaType == type }

    /** The session quota if available */
    val sessionQuota: UsageQuota?
        get() = quota(QuotaType.Session)

    /** The weekly quota if available */
    val weeklyQuota: UsageQuota?
        get() = quota(QuotaType.Weekly)

    /** All model-specific quotas */
    val modelSpecificQuotas: List<UsageQuota>
        get() = quotas.filter { it.quotaType is QuotaType.ModelSpecific }

    /**
     * The overall status is the worst status among all quotas.
     * This is a domain rule: overall health reflects the most critical issue.
     */
    val overallStatus: QuotaStatus
        get() = quotas.maxOfOrNull { it.status } ?: QuotaStatus.HEALTHY

    /**
     * The quota with the lowest remaining percentage.
     * Useful for determining which limit to highlight.
     */
    val lowestQuota: UsageQuota?
        get() = quotas.minByOrNull { it.percentRemaining }

    /** How long ago this snapshot was captured */
    val age: Duration
        get() = Clock.System.now() - capturedAt

    /** Whether this snapshot is considered stale (older than 5 minutes) */
    val isStale: Boolean
        get() = age > 5.minutes

    /** Human-readable age description */
    val ageDescription: String
        get() {
            val seconds = age.inWholeSeconds.toInt()
            return when {
                seconds < 60 -> "Just now"
                seconds < 3600 -> "${seconds / 60}m ago"
                else -> "${seconds / 3600}h ago"
            }
        }

    companion object {
        /** Creates an empty snapshot for when no data is available */
        fun empty(providerId: String): UsageSnapshot = UsageSnapshot(
            providerId = providerId,
            quotas = emptyList(),
            capturedAt = Clock.System.now()
        )
    }
}
