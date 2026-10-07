package com.tddworks.claudebar.quotas

/**
 * An amount of money in one currency, in nano-units (1 USD = 1_000_000_000),
 * exact to $0.000000001. Kotlin has no Decimal; the Swift face shows it as one. Two currencies are
 * never added or compared.
 */
data class Money(val amountNanos: Long, val currency: String = "USD")

/** HOW MUCH IS LEFT — a share or money, never both (CANONICAL_MODEL §5). */
sealed class Left {
    /** "62% left". */
    data class Share(val percent: Double) : Left()

    /**
     * "$12.40 remaining", "of $50.00". A balance with no ceiling has NO percentage —
     * writing 100% for it is the lie the status then believes.
     */
    data class Balance(val remaining: Money, val ceiling: Money?) : Left()
}

/**
 * WHEN IT REFILLS — the length is the provider's word, never guessed from a quota's
 * name. A prepaid balance has none. Times are seconds on the caller's clock.
 */
data class Window(val lengthSeconds: Double?, val resetsAtSeconds: Double?)
