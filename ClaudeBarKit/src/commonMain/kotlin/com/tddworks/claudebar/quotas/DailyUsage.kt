package com.tddworks.claudebar.quotas

import kotlin.native.ObjCName

/**
 * One day's usage, aggregated from a login's local logs.
 * Interim (CANONICAL_MODEL): leaves the kernel for `UsageHistory`; here because the snapshot carries it.
 */
data class DailyUsageStat(
    /** The day, as Unix seconds (since 1970). */
    val dateSeconds: Double,
    /** Estimated cost, including cache tokens. */
    val totalCostNanos: Long,
    /** Input + output tokens (or the log's own total when it keeps only that). */
    @ObjCName("totalTokens64") val totalTokens: Long,
    /** Wall-clock seconds across sessions. */
    val workingTime: Double,
    @ObjCName("sessionCount64") val sessionCount: Long,
    @ObjCName("inputTokens64") val inputTokens: Long,
    @ObjCName("outputTokens64") val outputTokens: Long,
    @ObjCName("cacheCreationTokens64") val cacheCreationTokens: Long,
    @ObjCName("cacheReadTokens64") val cacheReadTokens: Long,
    /** Estimated money saved by cache hits against the full input price. */
    val cachedSavingsNanos: Long,
) {
    val isEmpty: Boolean get() = totalTokens == 0L && totalCostNanos == 0L && workingTime == 0.0

    @ObjCName("totalTokensWithCache64")
    val totalTokensWithCache: Long get() = totalTokens + cacheCreationTokens + cacheReadTokens

    @ObjCName("totalCacheTokens64")
    val totalCacheTokens: Long get() = cacheCreationTokens + cacheReadTokens

    /** The share of input served from cache: read / (read + input); 0 when there is none. */
    val cacheHitRate: Double
        get() {
            val denominator = cacheReadTokens + inputTokens
            return if (denominator > 0) cacheReadTokens.toDouble() / denominator else 0.0
        }

    companion object {
        fun empty(dateSeconds: Double): DailyUsageStat = DailyUsageStat(dateSeconds, 0, 0, 0.0, 0, 0, 0, 0, 0, 0)
    }
}

/** Today's usage against a previous day. */
data class DailyUsageReport(val today: DailyUsageStat, val previous: DailyUsageStat) {
    /** Positive when today cost more. */
    val costDeltaNanos: Long get() = today.totalCostNanos - previous.totalCostNanos

    /** The cost change as a percentage of the previous day; null when that day cost nothing. */
    @ObjCName("costChangePercentOrNull")
    val costChangePercent: Double?
        get() = if (previous.totalCostNanos > 0) costDeltaNanos * 100.0 / previous.totalCostNanos else null

    @ObjCName("tokenDelta64")
    val tokenDelta: Long get() = today.totalTokens - previous.totalTokens

    @ObjCName("tokenChangePercentOrNull")
    val tokenChangePercent: Double?
        get() = if (previous.totalTokens > 0) tokenDelta.toDouble() / previous.totalTokens * 100 else null

    /** Working-time difference in seconds. */
    val timeDelta: Double get() = today.workingTime - previous.workingTime

    @ObjCName("timeChangePercentOrNull")
    val timeChangePercent: Double?
        get() = if (previous.workingTime > 0) timeDelta / previous.workingTime * 100 else null

    /** Today's share of the two days' cost, 0–1. */
    val costProgress: Double
        get() {
            val total = today.totalCostNanos + previous.totalCostNanos
            return if (total > 0) today.totalCostNanos.toDouble() / total else 0.0
        }

    val tokenProgress: Double
        get() {
            val total = today.totalTokens + previous.totalTokens
            return if (total > 0) today.totalTokens.toDouble() / total else 0.0
        }

    /** Whether working time is worth a card: either day has some. */
    val hasWorkingTime: Boolean get() = today.workingTime > 0 || previous.workingTime > 0

    val timeProgress: Double
        get() {
            val total = today.workingTime + previous.workingTime
            return if (total > 0) today.workingTime / total else 0.0
        }

    /** Cache hit rate change in fractional points (0.07 = +7pp). */
    val cacheHitRateDelta: Double get() = today.cacheHitRate - previous.cacheHitRate

    val savingsDeltaNanos: Long get() = today.cachedSavingsNanos - previous.cachedSavingsNanos

    @ObjCName("cacheTokenDelta64")
    val cacheTokenDelta: Long get() = today.totalCacheTokens - previous.totalCacheTokens
}
