package com.tddworks.claudebar.leaderboard

import kotlin.math.floor

/** The Mac's time zone: how far its clock is from UTC at an instant, daylight saving included. */
internal fun interface UtcOffset {
    fun secondsAt(unixSeconds: Double): Long
}

/**
 * The member's own calendar days, Gregorian, in the Mac's time zone — what a shared day is
 * dated by. Kotlin has no `Calendar`; the time zone is the only thing the Mac supplies.
 */
internal class MemberCalendar(private val offset: UtcOffset) {
    /** The local day holding `seconds`, `yyyy-MM-dd`. */
    fun day(seconds: Double): String {
        val (year, month, day) = civil(localDay(seconds))
        return "${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}"
    }

    /** The start of the local day holding `seconds`. */
    fun startOfDay(seconds: Double): Double = start(localDay(seconds))

    /** The start of the local day `days` before the one holding `seconds`. */
    fun startOfDay(seconds: Double, daysBefore: Int): Double = start(localDay(seconds) - daysBefore)

    private fun localDay(seconds: Double): Long = floor((seconds + offset.secondsAt(seconds)) / DAY).toLong()

    // Local midnight in UTC: the offset at midnight can differ from the one at noon, so it is read twice.
    private fun start(localDay: Long): Double {
        val midnight = (localDay * DAY).toDouble()
        val guess = midnight - offset.secondsAt(midnight)
        return midnight - offset.secondsAt(guess)
    }

    /** Days since 1970-01-01 → (year, month, day); Howard Hinnant's `civil_from_days`. */
    private fun civil(days: Long): Triple<Long, Long, Long> {
        val z = days + 719_468
        val era = (if (z >= 0) z else z - 146_096) / 146_097
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val day = doy - (153 * mp + 2) / 5 + 1
        val month = if (mp < 10) mp + 3 else mp - 9
        return Triple(yoe + era * 400 + if (month <= 2) 1 else 0, month, day)
    }

    private companion object {
        const val DAY = 86_400L
    }
}

/** A run of local calendar days, first to last, each held as the start of its day. */
internal data class DayRange(val firstSeconds: Double, val lastSeconds: Double) {
    companion object {
        fun of(firstSeconds: Double, lastSeconds: Double, calendar: MemberCalendar) =
            DayRange(calendar.startOfDay(firstSeconds), calendar.startOfDay(lastSeconds))

        /** The `count` days ending with the one that holds `daySeconds`. */
        fun last(count: Int, daySeconds: Double, calendar: MemberCalendar) =
            DayRange(calendar.startOfDay(daySeconds, maxOf(count, 1) - 1), calendar.startOfDay(daySeconds))
    }
}
