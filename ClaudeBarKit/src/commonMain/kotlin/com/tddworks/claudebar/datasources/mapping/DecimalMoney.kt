package com.tddworks.claudebar.datasources.mapping

/**
 * Decimal text as the kernel's money: nano-units, rounded half away from zero as the Swift face
 * rounds a `Decimal`. Read from the digits, never through a binary float, so `12.4` stays 12.4.
 */
internal object DecimalMoney {
    private const val NANO_PLACES = 9
    private val decimal = Regex("""^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$""")

    /** Decimal text only — never hex, `NaN` or a blank. */
    fun isDecimal(text: String): Boolean = decimal.matches(text)

    /** The nano-units [text] says; null when it isn't decimal text or doesn't fit. */
    fun nanos(text: String): Long? {
        if (!isDecimal(text)) return null
        val negative = text.startsWith('-')
        val unsigned = text.trimStart('+', '-')
        val mantissa = unsigned.substringBefore('e').substringBefore('E')
        val exponentText = unsigned.substring(mantissa.length).drop(1)
        val digits = mantissa.replace(".", "").trimStart('0')
        if (digits.isEmpty()) return 0
        val exponent = if (exponentText.isEmpty()) 0 else exponentText.toIntOrNull()?.coerceIn(-1000, 1000)
            ?: if (exponentText.startsWith('-')) -1000 else 1000
        return scaled(digits, leadingPoint(mantissa) + exponent + NANO_PLACES, negative)
    }

    /** A float's own shortest text, as `Decimal(Double)` reads it. */
    fun nanos(value: Double): Long? = if (value.isFinite()) nanos(value.toString()) else null

    /** The position of the point counted from the first significant digit of [mantissa]. */
    private fun leadingPoint(mantissa: String): Int {
        val integral = mantissa.substringBefore('.')
        val fraction = mantissa.substringAfter('.', "")
        val significantIntegral = integral.trimStart('0')
        return if (significantIntegral.isNotEmpty()) significantIntegral.length
        else -(fraction.length - fraction.trimStart('0').length)
    }

    private fun scaled(digits: String, point: Int, negative: Boolean): Long? {
        if (point > 19) return null
        val whole = if (point <= 0) "" else digits.take(point).padEnd(point, '0')
        val next = if (point < 0) '0' else digits.getOrElse(point) { '0' }
        var value = if (whole.isEmpty()) 0L else whole.toLongOrNull() ?: return null
        if (next >= '5') {
            if (value == Long.MAX_VALUE) return null
            value += 1
        }
        return if (negative) -value else value
    }
}
