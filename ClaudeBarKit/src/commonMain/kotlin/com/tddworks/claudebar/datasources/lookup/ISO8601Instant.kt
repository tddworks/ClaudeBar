package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.diagnostics.isoTimestamp
import kotlin.math.floor

/**
 * An ISO 8601 instant with any fraction of a second — `2026-07-26T21:03:09.138930Z` — read to
 * the millisecond, as seconds since 1970. Written back without a fraction, in UTC, the way
 * `ISO8601DateFormatter` writes it.
 */
internal object ISO8601Instant {
    private val shape = Regex("""^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$""")

    fun parse(text: String): Double? {
        val parts = shape.matchEntire(text)?.groupValues ?: return null
        val numbers = parts.subList(1, 7).map { it.toLong() }
        val (year, month, day, hour, minute) = numbers
        val second = numbers[5]
        if (month !in 1..12 || day !in 1..31 || hour > 23 || minute > 59 || second > 60) return null
        val millis = parts[7].take(3).padEnd(3, '0').toLong()
        val zone = parts[8]
        val offset = if (zone == "Z") 0L else {
            val digits = zone.drop(1).replace(":", "")
            val seconds = digits.take(2).toLong() * 3600 + digits.drop(2).toLong() * 60
            if (zone[0] == '-') -seconds else seconds
        }
        val days = daysFromCivil(year, month, day)
        return (days * 86_400 + hour * 3600 + minute * 60 + second - offset) + millis / 1000.0
    }

    /** `2023-11-14T22:13:20Z`. */
    fun format(seconds: Double): String = isoTimestamp(floor(seconds).toLong() * 1000).substringBefore('.') + "Z"

    /** Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm). */
    private fun daysFromCivil(year: Long, month: Long, day: Long): Long {
        val y = if (month <= 2) year - 1 else year
        val era = y.floorDiv(400L)
        val yoe = y - era * 400
        val doy = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/** A value as a person meant it: no surrounding whitespace or newlines. */
internal fun trimmed(value: String): String = value.trim()
