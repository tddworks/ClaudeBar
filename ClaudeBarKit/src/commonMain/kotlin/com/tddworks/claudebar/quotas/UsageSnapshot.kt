package com.tddworks.claudebar.quotas

/**
 * A provider's usage at one moment — every quota, and the cost, plan and history beside them.
 * Interim shape (CANONICAL_MODEL): becomes `Usage`.
 */
data class UsageSnapshot(
    val providerId: String,
    /** Every quota captured; empty for API accounts. */
    val quotas: List<UsageQuota>,
    val capturedAtSeconds: Double,
    val accountEmail: String?,
    val accountOrganization: String?,
    val loginMethod: String?,
    val accountTier: AccountTier?,
    val costUsage: CostUsage?,
    val dailyUsageReport: DailyUsageReport?,
    val extensionMetrics: List<ExtensionMetric>?,
) {
    fun quota(type: QuotaType): UsageQuota? = quotas.firstOrNull { it.quotaType == type }

    /** The quota a persisted key names. */
    fun quotaForKey(key: String): UsageQuota? = QuotaType.fromQuotaKey(key)?.let(::quota)

    val sessionQuota: UsageQuota? get() = quota(QuotaType.Session)
    val weeklyQuota: UsageQuota? get() = quota(QuotaType.Weekly)
    val modelSpecificQuotas: List<UsageQuota> get() = quotas.filter { it.quotaType is QuotaType.ModelSpecific }

    /** Whether any quota or metric is tagged with an upstream account (aggregating providers). */
    val hasQuotaGroups: Boolean
        get() = quotas.any { it.group != null } || extensionMetrics.orEmpty().any { it.group != null }

    /**
     * Quotas by group, in order of first appearance; ungrouped ones form one unnamed group.
     * A grouped metric becomes a note: on its group's section, or a note-only section after.
     */
    val quotaGroups: List<QuotaGroup>
        get() {
            val order = mutableListOf<String>()
            val buckets = mutableMapOf<String, MutableList<UsageQuota>>()
            for (quota in quotas) {
                val key = quota.group ?: ""
                if (key !in buckets) order += key
                buckets.getOrPut(key) { mutableListOf() } += quota
            }
            val notes = mutableMapOf<String, String>()
            for (metric in extensionMetrics.orEmpty()) {
                val group = metric.group ?: continue
                if (group !in buckets && group !in notes) order += group
                notes[group] = notes[group]?.let { "$it\n${metric.value}" } ?: metric.value
            }
            return order.map { key -> QuotaGroup(key.ifEmpty { null }, buckets[key].orEmpty(), notes[key]) }
        }

    /**
     * The same usage without the quotas a person hid (#140), by quota key. Keys no longer
     * reported match nothing; hiding every quota hides none.
     */
    fun hiding(keys: Set<String>): UsageSnapshot {
        if (keys.isEmpty()) return this
        val watched = quotas.filter { it.quotaType.quotaKey !in keys }
        if (watched.isEmpty() || watched.size == quotas.size) return this
        return copy(quotas = watched)
    }

    /** The worst quota's status: overall health is the most critical issue. */
    val overallStatus: QuotaStatus get() = quotas.maxOfOrNull { it.status } ?: QuotaStatus.HEALTHY

    fun paceAwareOverallStatus(burnRateThreshold: Double, nowSeconds: Double): QuotaStatus =
        quotas.maxOfOrNull { it.paceAwareStatus(burnRateThreshold, nowSeconds) } ?: QuotaStatus.HEALTHY

    /** The worst quota's status under the person's policy. */
    fun overallStatus(under: StatusPolicy, nowSeconds: Double): QuotaStatus =
        quotas.maxOfOrNull { it.status(under, nowSeconds) } ?: QuotaStatus.HEALTHY

    /** The quota with the least left; a balance is the lowest only when nothing else is. */
    val lowestQuota: UsageQuota? get() = lowest(quotas)

    /** Seconds since capture. */
    fun age(nowSeconds: Double): Double = nowSeconds - capturedAtSeconds

    /** Older than five minutes. */
    fun isStale(nowSeconds: Double): Boolean = age(nowSeconds) > 300

    /** "Just now", "4m ago", "2h ago". */
    fun ageDescription(nowSeconds: Double): String {
        val seconds = age(nowSeconds).toLong()
        return when {
            seconds < 60 -> "Just now"
            seconds < 3600 -> "${seconds / 60}m ago"
            else -> "${seconds / 3600}h ago"
        }
    }

    companion object {
        /** No usage yet. */
        fun empty(providerId: String, nowSeconds: Double): UsageSnapshot =
            UsageSnapshot(providerId, emptyList(), nowSeconds, null, null, null, null, null, null, null)
    }
}

/** One section of quotas from a single upstream account; `title` is null for the ungrouped ones. */
data class QuotaGroup(
    val title: String?,
    val quotas: List<UsageQuota>,
    /** A note for a section without usable quota data ("No usage reported"). */
    val note: String?,
) {
    /** The most critical status within — shown while collapsed. */
    val worstStatus: QuotaStatus get() = quotas.maxOfOrNull { it.status } ?: QuotaStatus.HEALTHY

    /** The quota with the least headroom — summarized while collapsed. */
    val lowestQuota: UsageQuota? get() = lowest(quotas)

    /** A note-only section shows its note in the header; otherwise as its own row. */
    val noteIsHeader: Boolean get() = quotas.isEmpty()
}

private fun lowest(quotas: List<UsageQuota>): UsageQuota? =
    quotas.filter { it.percentLeft != null }.minByOrNull { it.percentRemaining }
        ?: quotas.minByOrNull { it.percentRemaining }
