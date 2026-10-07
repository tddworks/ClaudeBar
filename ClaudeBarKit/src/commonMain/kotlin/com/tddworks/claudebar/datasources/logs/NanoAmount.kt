package com.tddworks.claudebar.datasources.logs

/**
 * Money in nano-units, with what lies below a nano kept apart in billionths of one, so a
 * day's sum of per-token prices stays exact where Swift summed `Decimal`s, and rounds once —
 * half away from zero, as Swift's `Decimal.nanos` does — when the day is made. Exact to
 * 10⁻¹⁸ of a dollar: 18 decimal places, where `Decimal` kept 38 significant digits.
 */
internal data class NanoAmount(val nanos: Long, val belowNano: Long = 0) {
    init {
        require(belowNano in 0 until SUB) { "belowNano is billionths of one nano" }
    }

    operator fun plus(other: NanoAmount) = of(nanos + other.nanos, belowNano + other.belowNano)

    operator fun minus(other: NanoAmount) = of(nanos - other.nanos, belowNano - other.belowNano)

    /**
     * [tokens] at this price per [per] tokens: tokens × amount × den / num, split so no product
     * leaves a Long. Exact while `per` divides 10⁹ × its own numerator — 1, 1000, 1000000.
     */
    fun forTokens(tokens: Long, per: Per): NanoAmount {
        val scaled = nanos * per.denominator
        val restTokens = tokens * scaled.mod(per.numerator)
        val whole = tokens * scaled.floorDiv(per.numerator) + restTokens.floorDiv(per.numerator)
        var below = (restTokens.mod(per.numerator) * SUB).floorDiv(per.numerator)
        if (belowNano != 0L) below += (tokens * belowNano * per.denominator).floorDiv(per.numerator)
        return of(whole, below)
    }

    /** Whole nanos, half away from zero. */
    fun rounded(): Long = when {
        nanos >= 0 -> if (belowNano >= SUB / 2) nanos + 1 else nanos
        else -> if (belowNano > SUB / 2) nanos + 1 else nanos
    }

    /** `per` in a price file: tokens per price, an exact fraction. */
    data class Per(val numerator: Long, val denominator: Long) {
        init {
            require(numerator > 0 && denominator > 0) { "per is a positive amount" }
        }
    }

    companion object {
        private const val SUB = 1_000_000_000L
        val ZERO = NanoAmount(0)

        private fun of(nanos: Long, below: Long) = NanoAmount(nanos + below.floorDiv(SUB), below.mod(SUB))

        private val decimal = Regex("""^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$""")

        /** An amount as written — `"0.30"`, `0.0123`, `1e-5` — read exactly to 18 places; null when it isn't one. */
        fun parse(text: String): NanoAmount? {
            val match = decimal.matchEntire(text.trim()) ?: return null
            val (sign, integer, fraction, exponent) = match.destructured
            if (integer.isEmpty() && fraction.isEmpty()) return null
            val exp = exponent.ifEmpty { "0" }.toIntOrNull()?.takeIf { it in -400..400 } ?: return null
            // The amount in billionths of a nano: its digits moved by the exponent, past 18 places dropped.
            val shift = exp - fraction.length + 18
            val digits = (integer + fraction).let { if (shift >= 0) it + "0".repeat(shift) else it.dropLast(-shift) }
                .trimStart('0').ifEmpty { "0" }
            if (digits.length > 27) return null
            val amount = NanoAmount(digits.dropLast(9).ifEmpty { "0" }.toLong(), digits.takeLast(9).toLong())
            return if (sign == "-") ZERO - amount else amount
        }

        /** `per` as written; null unless it is a positive amount. */
        fun per(text: String): Per? {
            val match = decimal.matchEntire(text.trim()) ?: return null
            val (sign, integer, fraction, exponent) = match.destructured
            if (sign == "-" || (integer.isEmpty() && fraction.isEmpty())) return null
            val digits = (integer + fraction).trimStart('0').ifEmpty { return null }
            val shift = (exponent.ifEmpty { "0" }.toIntOrNull() ?: return null) - fraction.length
            if (digits.length + maxOf(shift, 0) > 18 || -shift > 18) return null
            return if (shift >= 0) Per(digits.toLong() * pow10(shift), 1) else Per(digits.toLong(), pow10(-shift))
        }

        private fun pow10(n: Int): Long {
            var result = 1L
            repeat(n) { result *= 10 }
            return result
        }
    }
}
