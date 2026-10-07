package com.tddworks.claudebar.quotas

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * One usage quota measurement for a provider — the value every card, the menu bar and
 * the status color read.
 *
 * Times are seconds on the caller's clock: the kernel only ever subtracts `nowSeconds`
 * from them, so any epoch works as long as `now` uses the same one. Money is micro-units.
 *
 * Interim shape (CANONICAL_MODEL): becomes `Quota` with `left: Left` — a share OR money.
 */
class UsageQuota(
    percentRemaining: Double,
    val quotaType: QuotaType,
    /** The provider this quota belongs to ("claude", "codex"). */
    val providerId: String,
    val resetsAtSeconds: Double?,
    /** Raw reset text from a CLI ("Resets 11am"). */
    val resetText: String?,
    /** The window's length when the data source states it; pace is unknown without it. */
    val windowSeconds: Double?,
    /** Balance remaining for a credit quota with no cap. */
    val dollarRemainingMicros: Long?,
    /** Spent, for a capped spend meter. */
    val dollarUsedMicros: Long?,
    /** The cap, for a capped spend meter. */
    val dollarCapMicros: Long?,
    /** Section when an aggregating provider spans several accounts ("Claude · work"). */
    val group: String?,
    /** Short card title inside its group ("5h", "Spark 7d"). */
    val compactTitle: String?,
    /** Menu-bar window title when the full label is too wide. */
    val menuBarTitle: String?,
    /** ISO 4217 code for money quotas; null means USD. */
    val currency: String?,
) {
    /** The percentage left; negative when over quota, never above 100. */
    val percentRemaining: Double = min(100.0, percentRemaining)

    /**
     * HOW MUCH IS LEFT — what status, pace and the menu bar compare. Today's shape wrote
     * a balance with no ceiling as 100%; that reads as money here.
     */
    val left: Left = run {
        val code = currency ?: "USD"
        when {
            dollarRemainingMicros != null && dollarCapMicros == null && percentRemaining == 100.0 ->
                Left.Balance(Money(dollarRemainingMicros, code), null)
            dollarRemainingMicros != null && dollarCapMicros != null ->
                Left.Balance(Money(dollarRemainingMicros, code), Money(dollarCapMicros, code))
            else -> Left.Share(min(100.0, percentRemaining))
        }
    }

    /** A quota in the model's shape: what is left, and the window it refills in. */
    constructor(
        left: Left,
        quotaType: QuotaType,
        providerId: String,
        resetsAtSeconds: Double?,
        resetText: String?,
        windowSeconds: Double?,
        group: String?,
        compactTitle: String?,
        menuBarTitle: String?,
    ) : this(
        percentRemaining = when (left) {
            is Left.Share -> left.percent
            is Left.Balance -> left.ceiling?.let { share(left.remaining, it) } ?: 100.0
        },
        quotaType = quotaType,
        providerId = providerId,
        resetsAtSeconds = resetsAtSeconds,
        resetText = resetText,
        windowSeconds = windowSeconds,
        dollarRemainingMicros = (left as? Left.Balance)?.remaining?.amountMicros,
        dollarUsedMicros = (left as? Left.Balance)?.let { b -> b.ceiling?.let { it.amountMicros - b.remaining.amountMicros } },
        dollarCapMicros = (left as? Left.Balance)?.ceiling?.amountMicros,
        group = group,
        compactTitle = compactTitle,
        menuBarTitle = menuBarTitle,
        currency = (left as? Left.Balance)?.remaining?.currency,
    )

    companion object {
        private fun share(remaining: Money, ceiling: Money): Double? =
            if (ceiling.currency != remaining.currency || ceiling.amountMicros <= 0) null
            else remaining.amountMicros * 100.0 / ceiling.amountMicros

        /** The display symbol for an ISO 4217 code ("USD" → "$"); unknown codes keep the code. */
        fun currencySymbol(code: String): String = when (code.uppercase()) {
            "USD", "US", "US$" -> "$"
            "CNY", "CNH", "RMB", "CN", "¥" -> "¥"
            "EUR" -> "€"
            "GBP" -> "£"
            "JPY" -> "¥"
            "HKD" -> "HK$"
            "KRW" -> "₩"
            "SGD" -> "S$"
            else -> code.uppercase() + " "
        }
    }

    override fun equals(other: Any?): Boolean =
        other is UsageQuota && percentRemaining == other.percentRemaining && quotaType == other.quotaType &&
            providerId == other.providerId && resetsAtSeconds == other.resetsAtSeconds &&
            resetText == other.resetText && windowSeconds == other.windowSeconds &&
            dollarRemainingMicros == other.dollarRemainingMicros && dollarUsedMicros == other.dollarUsedMicros &&
            dollarCapMicros == other.dollarCapMicros && group == other.group &&
            compactTitle == other.compactTitle && menuBarTitle == other.menuBarTitle && currency == other.currency

    override fun hashCode(): Int = listOf(
        percentRemaining, quotaType, providerId, resetsAtSeconds, resetText, windowSeconds, dollarRemainingMicros,
        dollarUsedMicros, dollarCapMicros, group, compactTitle, menuBarTitle, currency,
    ).hashCode()

    override fun toString(): String = "UsageQuota($providerId ${quotaType.quotaKey} $percentRemaining% left=$left)"

    /** The percentage left — null for a balance with no ceiling, which has none. */
    val percentLeftOrNull: Double?
        get() = when (val left = left) {
            is Left.Share -> left.percent
            is Left.Balance -> left.ceiling?.let { share(left.remaining, it) ?: percentRemaining }
        }

    /** Whether this is a balance with no ceiling. */
    val isBalance: Boolean get() = (left as? Left.Balance)?.let { it.ceiling == null } ?: false

    /** WHEN IT REFILLS, as the data source stated it. */
    val window: Window?
        get() = if (windowSeconds == null && resetsAtSeconds == null) null else Window(windowSeconds, resetsAtSeconds)

    /** The status by the thresholds; a balance is healthy until it runs out. */
    val status: QuotaStatus
        get() {
            val left = left
            if (left is Left.Balance && left.ceiling == null) {
                return if (left.remaining.amountMicros <= 0) QuotaStatus.DEPLETED else QuotaStatus.HEALTHY
            }
            return QuotaStatus.from(percentRemaining)
        }

    val percentUsed: Double get() = 100 - percentRemaining
    val isDepleted: Boolean get() = percentRemaining <= 0
    val isDollarBased: Boolean get() = dollarRemainingMicros != null
    val needsAttention: Boolean get() = status.needsAttention

    /** This quota's status under the person's policy. */
    fun status(under: StatusPolicy, nowSeconds: Double): QuotaStatus = when (under) {
        StatusPolicy.Absolute -> status
        is StatusPolicy.PaceAware -> paceAwareStatus(under.burnRateThreshold, nowSeconds)
    }

    /** Pace-aware status when the window is known; absolute thresholds otherwise. */
    fun paceAwareStatus(burnRateThreshold: Double, nowSeconds: Double): QuotaStatus {
        val elapsed = percentTimeElapsed(nowSeconds) ?: return status
        return QuotaStatus.from(percentRemaining, elapsed, burnRateThreshold)
    }

    /** Seconds until the reset, never negative; null when the reset is unknown. */
    fun timeUntilReset(nowSeconds: Double): Double? = resetsAtSeconds?.let { max(0.0, it - nowSeconds) }

    /** How much of the window has elapsed (0–100); null without a stated window. */
    fun percentTimeElapsed(nowSeconds: Double): Double? {
        if (isBalance) return null
        val untilReset = timeUntilReset(nowSeconds) ?: return null
        val total = windowSeconds?.takeIf { it > 0 } ?: return null
        return min(100.0, max(0.0, (total - untilReset) / total * 100))
    }

    /** How fast quota is used against the clock; 1.0 is exactly on pace. */
    fun burnRate(nowSeconds: Double): Double? {
        val elapsed = percentTimeElapsed(nowSeconds)?.takeIf { it > 0 } ?: return null
        return percentUsed / elapsed
    }

    /** Usage minus expected usage: positive ahead, negative behind. */
    fun pacePercent(nowSeconds: Double): Double? = percentTimeElapsed(nowSeconds)?.let { percentUsed - it }

    fun pace(nowSeconds: Double): UsagePace {
        val elapsed = percentTimeElapsed(nowSeconds) ?: return UsagePace.UNKNOWN
        return UsagePace.from(percentUsed, elapsed)
    }

    /** "37% below expected usage"; null when pace is unknown. */
    fun paceInsight(nowSeconds: Double): String? {
        val pacePercent = pacePercent(nowSeconds) ?: return null
        val delta = abs(pacePercent).toInt()
        return when (pace(nowSeconds)) {
            UsagePace.BEHIND -> "$delta% below expected usage"
            UsagePace.AHEAD -> "$delta% above expected usage"
            UsagePace.ON_PACE -> "Right on track"
            UsagePace.UNKNOWN -> null
        }
    }

    /** The expected-pace tick's level; null when it cannot be graded. */
    fun paceLevel(nowSeconds: Double): PaceLevel? =
        percentTimeElapsed(nowSeconds)?.let { PaceLevel.from(percentUsed, it) }

    /** "1d", "3:58", "45m", "soon"; null when the reset is unknown. */
    fun compactResetTime(nowSeconds: Double): String? {
        val s = timeUntilReset(nowSeconds)?.toLong() ?: return null
        return when {
            s >= 86400 -> "${s / 86400}d"
            s >= 3600 -> "${s / 3600}:${((s % 3600) / 60).toString().padStart(2, '0')}"
            s >= 60 -> "${s / 60}m"
            else -> "soon"
        }
    }

    /** "Resets in 2d 5h 30m"; null when the reset is unknown. */
    fun resetTimestampDescription(nowSeconds: Double): String? {
        val untilReset = timeUntilReset(nowSeconds) ?: return null
        val totalMinutes = (untilReset / 60).toLong()
        val days = totalMinutes / (24 * 60)
        val hours = (totalMinutes % (24 * 60)) / 60
        val minutes = totalMinutes % 60
        val parts = buildList {
            if (days > 0) add("${days}d")
            if (hours > 0) add("${hours}h")
            if (minutes > 0) add("${minutes}m")
        }
        return if (parts.isEmpty()) "Resets soon" else "Resets in ${parts.joinToString(" ")}"
    }

    /** "Resets in 3h 20m"; null when the reset is unknown. */
    fun resetDescription(nowSeconds: Double): String? {
        val untilReset = timeUntilReset(nowSeconds) ?: return null
        val hours = (untilReset / 3600).toLong()
        val minutes = ((untilReset % 3600) / 60).toLong()
        return when {
            hours > 24 -> "Resets in ${hours / 24}d ${hours % 24}h"
            hours > 0 -> "Resets in ${hours}h ${minutes}m"
            minutes > 0 -> "Resets in ${minutes}m"
            else -> "Resets soon"
        }
    }
}
