package com.tddworks.claudebar.alerting

/**
 * The Notify! gateway's field limits, enforced by every value at construction. The gateway
 * rejects an oversized string with a 400 and clamps a number; ClaudeBar shortens and clamps
 * itself, so a long label shortens rather than failing to reach the phone.
 */
internal object NotifyLimits {
    // Live Activity tile
    const val TITLE_LENGTH = 120
    const val BODY_LENGTH = 300
    const val SYMBOL_LENGTH = 64
    const val TRAILING_LENGTH = 40
    const val STATUS_LENGTH = 40
    const val METRIC_COUNT = 6
    const val METRIC_LABEL_LENGTH = 24
    const val METRIC_VALUE_LENGTH = 16
    const val METRIC_UNIT_LENGTH = 8

    // Widget
    const val WIDGET_TITLE_LENGTH = 120
    const val WIDGET_VALUE_LENGTH = 40
    const val WIDGET_UNIT_LENGTH = 12
    const val WIDGET_DETAIL_LENGTH = 120

    /**
     * Trimmed, without NUL (the gateway refuses it), at most [maximum] characters; empty is
     * null, so an absent field is never sent as "".
     */
    fun text(value: String?, maximum: Int): String? {
        if (value == null) return null
        val cleaned = value.replace("\u0000", "").trim()
        if (cleaned.isEmpty()) return null
        return cleaned.prefixOfCharacters(maximum)
    }

    /** Clamped to 0–100; an over-limit quota's negative remainder reads as an empty bar. */
    fun progress(value: Double?): Double? {
        if (value == null || !value.isFinite()) return null
        return value.coerceIn(0.0, 100.0)
    }

    /** `#RRGGBB` or `#AARRGGBB` in uppercase, or null so a bad color is dropped, not fatal. */
    fun tint(value: String?): String? {
        if (value == null) return null
        val trimmed = value.trim()
        val digits = trimmed.removePrefix("#")
        if (digits.length != 6 && digits.length != 8) return null
        if (!digits.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return "#" + digits.uppercase()
    }

    /** The first [maximum] characters, never splitting a surrogate pair. */
    private fun String.prefixOfCharacters(maximum: Int): String {
        var end = 0
        var count = 0
        while (end < length && count < maximum) {
            end += if (this[end].isHighSurrogate() && end + 1 < length && this[end + 1].isLowSurrogate()) 2 else 1
            count++
        }
        return substring(0, end)
    }
}
