package com.tddworks.claudebar.quotas

/**
 * An amount of money in one currency. Kotlin common code has no `Decimal`, so the
 * spike keeps minor units (cents); two currencies are never compared.
 */
data class Money(val minorUnits: Long, val currency: String = "USD")

/** HOW MUCH IS LEFT — a share or money, never both (CANONICAL_MODEL §5). */
sealed interface Left {
    data class Share(val percent: Double) : Left
    data class Balance(val remaining: Money, val ceiling: Money?) : Left
}

/**
 * A quota in the model's shape. The window's length is the provider's word, never
 * guessed from the name. Times are epoch milliseconds so the clock stays the caller's.
 */
data class Quota(
    val left: Left,
    val type: QuotaType,
    val providerId: String,
    val resetsAtMillis: Long? = null,
    val windowMillis: Long? = null,
) {
    val percentLeft: Double?
        get() = when (left) {
            is Left.Share -> left.percent.coerceAtMost(100.0)
            is Left.Balance -> left.ceiling
                ?.takeIf { it.currency == left.remaining.currency && it.minorUnits > 0 }
                ?.let { left.remaining.minorUnits * 100.0 / it.minorUnits }
        }

    val status: QuotaStatus
        get() {
            if (left is Left.Balance && left.ceiling == null) {
                return if (left.remaining.minorUnits <= 0) QuotaStatus.DEPLETED else QuotaStatus.HEALTHY
            }
            return QuotaStatus.from(percentLeft ?: 100.0)
        }

    fun percentTimeElapsed(nowMillis: Long): Double? {
        if (left is Left.Balance && left.ceiling == null) return null
        val resetsAt = resetsAtMillis ?: return null
        val window = windowMillis?.takeIf { it > 0 } ?: return null
        val elapsed = window - (resetsAt - nowMillis)
        return (elapsed * 100.0 / window).coerceIn(0.0, 100.0)
    }

    fun status(under: StatusPolicy, nowMillis: Long): QuotaStatus = when (under) {
        StatusPolicy.Absolute -> status
        is StatusPolicy.PaceAware -> {
            val elapsed = percentTimeElapsed(nowMillis)
            val percent = percentLeft
            if (elapsed == null || percent == null) status else QuotaStatus.from(percent, elapsed)
        }
    }
}

/** The worst quota's status under the person's policy. */
fun List<Quota>.overallStatus(under: StatusPolicy, nowMillis: Long): QuotaStatus =
    maxOfOrNull { it.status(under, nowMillis) } ?: QuotaStatus.HEALTHY
