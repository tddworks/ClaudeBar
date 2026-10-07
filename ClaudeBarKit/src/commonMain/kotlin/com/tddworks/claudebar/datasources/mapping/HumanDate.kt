package com.tddworks.claudebar.datasources.mapping

import kotlin.math.floor

/** The time zones this machine knows — what a wall-clock time in a named zone means. */
internal interface TimeZones {
    /** The zone the app runs in ("Europe/Amsterdam"). */
    val current: String

    /** How far [zone] is ahead of UTC at [atSeconds] (Unix), in seconds; null for a zone it doesn't know. */
    fun offsetSeconds(zone: String, atSeconds: Double): Int?
}

/** This machine's zones. */
internal expect fun systemTimeZones(): TimeZones

/**
 * Reset times as CLIs print them for people — "2h 15m", "4:59pm (America/New_York)",
 * "Jan 15, 3:30pm", "Dec 25 at 4:59am", "Jan 1, 2026" — turned into the next instant they
 * name (Unix seconds). A text format, not a vendor's: a mapping script reaches it as `humanDate(text)`.
 */
internal object HumanDate {
    fun parse(text: String, nowSeconds: Double, zones: TimeZones = systemTimeZones()): Double? =
        relative(text, nowSeconds) ?: absolute(text, nowSeconds, zones)

    private val units = listOf(
        Regex("""(\d+)\s*d(?:ays?)?""") to 86400.0,
        Regex("""(\d+)\s*h(?:ours?|r)?""") to 3600.0,
        Regex("""(\d+)\s*m(?:in(?:utes?)?)?""") to 60.0,
    )

    /** "2d", "3h", "15m", "2 hours 5 min" — the sum of the first of each unit. */
    private fun relative(text: String, nowSeconds: Double): Double? {
        var total = 0.0
        for ((pattern, seconds) in units) {
            val count = pattern.find(text)?.value?.filter { it.isDigit() }?.toIntOrNull() ?: continue
            total += count * seconds
        }
        return if (total > 0) nowSeconds + total else null
    }

    private val percentAtEnd = Regex("""\s+\d{1,3}%\s*(?:used|left)\s*$""")
    private val zoneAtEnd = Regex("""\s*\([^)]+\)\s*$""")
    private val at = Regex("""\s+at\s+""")
    private val zoneInText = Regex("""\(([^)]+)\)""")

    /** A date and/or time, optionally followed by an IANA zone in parentheses. */
    private fun absolute(text: String, nowSeconds: Double, zones: TimeZones): Double? {
        val zone = zoneInText.findAll(text).lastOrNull()?.groupValues?.get(1)?.trim(::isBlankInLine)
            ?.takeIf { zones.offsetSeconds(it, nowSeconds) != null }
            ?: zones.current

        var cleaned = percentAtEnd.replace(text, "")
        val lastResets = cleaned.lastIndexOf("resets", ignoreCase = true)
        if (lastResets >= 0) cleaned = cleaned.substring(lastResets + "resets".length)
        cleaned = at.replace(zoneAtEnd.replace(cleaned, "").trim(::isBlankInLine), ", ")

        for (format in Format.entries) {
            val parsed = format.read(cleaned) ?: continue
            return future(parsed, format, zone, zones, nowSeconds)
        }
        return null
    }

    /** What a format read: the fields it has. */
    private class Fields(val month: Int?, val day: Int?, val year: Int?, val hour: Int?, val minute: Int)

    /** The formats tried, most specific first — `MMM d, yyyy, h:mma` … `MMM d`. */
    private enum class Format(pattern: String, val hasMonth: Boolean, val hasYear: Boolean, val hasTime: Boolean) {
        DATE_YEAR_TIME("""$MONTH\s+(\d{1,2}),\s*(\d{4}),\s*(\d{1,2}):(\d{2})\s*$MERIDIEM""", true, true, true),
        DATE_YEAR_HOUR("""$MONTH\s+(\d{1,2}),\s*(\d{4}),\s*(\d{1,2})\s*$MERIDIEM""", true, true, true),
        DATE_YEAR("""$MONTH\s+(\d{1,2}),\s*(\d{4})""", true, true, false),
        DATE_TIME("""$MONTH\s+(\d{1,2}),\s*(\d{1,2}):(\d{2})\s*$MERIDIEM""", true, false, true),
        DATE_HOUR("""$MONTH\s+(\d{1,2}),\s*(\d{1,2})\s*$MERIDIEM""", true, false, true),
        TIME("""(\d{1,2}):(\d{2})\s*$MERIDIEM""", false, false, true),
        HOUR("""(\d{1,2})\s*$MERIDIEM""", false, false, true),
        DATE("""$MONTH\s+(\d{1,2})""", true, false, false);

        private val regex = Regex("^$pattern$", RegexOption.IGNORE_CASE)

        fun read(text: String): Fields? {
            val groups = regex.matchEntire(text)?.groupValues?.drop(1) ?: return null
            var next = 0
            val month = if (hasMonth) monthNumber(groups[next++]) ?: return null else null
            val day = if (hasMonth) groups[next++].toInt().takeIf { it in 1..daysIn(month!!) } ?: return null else null
            val year = if (hasYear) groups[next++].toInt() else null
            if (!hasTime) return Fields(month, day, year, null, 0)
            val hour12 = groups[next++].toInt().takeIf { it in 1..12 } ?: return null
            val minute = if (this == TIME || this == DATE_TIME || this == DATE_YEAR_TIME) {
                groups[next++].toInt().takeIf { it in 0..59 } ?: return null
            } else 0
            val pm = groups[next].equals("pm", ignoreCase = true)
            return Fields(month, day, year, hour12 % 12 + if (pm) 12 else 0, minute)
        }
    }

    /** The instant a parsed date names: the next one when it came without a year, or without a day. */
    private fun future(fields: Fields, format: Format, zone: String, zones: TimeZones, nowSeconds: Double): Double {
        val today = Civil.of(nowSeconds, zone, zones)
        val hour = fields.hour ?: 0
        if (format.hasYear) return Civil(fields.year!!, fields.month!!, fields.day!!, hour, fields.minute).seconds(zone, zones)
        if (format.hasMonth) {
            val thisYear = Civil(today.year, fields.month!!, fields.day!!, hour, fields.minute).seconds(zone, zones)
            if (thisYear > nowSeconds) return thisYear
            return Civil(today.year + 1, fields.month, fields.day, hour, fields.minute).seconds(zone, zones)
        }
        val todays = Civil(today.year, today.month, today.day, hour, fields.minute).seconds(zone, zones)
        if (todays > nowSeconds) return todays
        val tomorrow = Civil.of(nowSeconds + 86400, zone, zones)
        return Civil(tomorrow.year, tomorrow.month, tomorrow.day, hour, fields.minute).seconds(zone, zones)
    }

    /** A wall-clock time in some zone, proleptic Gregorian. */
    private data class Civil(val year: Int, val month: Int, val day: Int, val hour: Int = 0, val minute: Int = 0) {
        /** The instant this wall-clock time names in [zone]. */
        fun seconds(zone: String, zones: TimeZones): Double {
            val wall = (daysFromCivil(year, month, day) * 86400L + hour * 3600L + minute * 60L).toDouble()
            val guess = wall - (zones.offsetSeconds(zone, wall) ?: 0)
            return wall - (zones.offsetSeconds(zone, guess) ?: 0)
        }

        companion object {
            fun of(seconds: Double, zone: String, zones: TimeZones): Civil {
                val wall = floor(seconds).toLong() + (zones.offsetSeconds(zone, seconds) ?: 0)
                val days = wall.floorDiv(86400L)
                val rest = wall - days * 86400
                return civilFromDays(days).let { (y, m, d) -> Civil(y, m, d, (rest / 3600).toInt(), ((rest % 3600) / 60).toInt()) }
            }
        }
    }

    private const val MONTH = """([A-Za-z]+)"""
    private const val MERIDIEM = """(am|pm)"""
    private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private val monthNames = listOf(
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    )

    /** "Jan" or "January", any case. */
    private fun monthNumber(text: String): Int? {
        val lower = text.lowercase()
        val index = months.indexOf(lower).takeIf { it >= 0 } ?: monthNames.indexOf(lower).takeIf { it >= 0 } ?: return null
        return index + 1
    }

    /** A day a year without one may still hold — February has 29. */
    private fun daysIn(month: Int) = when (month) {
        2 -> 29
        4, 6, 9, 11 -> 30
        else -> 31
    }

    /** Foundation's `.whitespaces`: spaces and tabs, never a line break. */
    private fun isBlankInLine(c: Char) = c == '\t' || c.category == CharCategory.SPACE_SEPARATOR
}

/** Days since 1970-01-01 of a Gregorian date (Howard Hinnant's algorithm). */
internal fun daysFromCivil(year: Int, month: Int, day: Int): Long {
    val y = (if (month <= 2) year - 1 else year).toLong()
    val era = y.floorDiv(400L)
    val yoe = y - era * 400
    val doy = (153 * (month + (if (month > 2) -3 else 9)) + 2) / 5 + day - 1
    val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/** The Gregorian date of a day since 1970-01-01. */
internal fun civilFromDays(days: Long): Triple<Int, Int, Int> {
    val z = days + 719468
    val era = z.floorDiv(146097L)
    val doe = z - era * 146097
    val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    val mp = (5 * doy + 2) / 153
    val day = (doy - (153 * mp + 2) / 5 + 1).toInt()
    val month = (if (mp < 10) mp + 3 else mp - 9).toInt()
    val year = (yoe + era * 400 + if (month <= 2) 1 else 0).toInt()
    return Triple(year, month, day)
}
