package com.tddworks.claudebar.datasources.logs

/**
 * A run of local calendar days, first to last — what a page asks usage history for: the
 * last two for *TODAY'S USAGE*, thirty for a chart. Each end is the start of its day.
 * Swift keeps it in Quotas; it lives here until the kernel has one.
 */
@ConsistentCopyVisibility
internal data class DateRange private constructor(val firstSeconds: Double, val lastSeconds: Double) {
    constructor(firstSeconds: Double, lastSeconds: Double, calendar: LocalCalendar) :
        this(calendar.startOfDay(firstSeconds), calendar.startOfDay(lastSeconds))

    /** The start of every day in the range, in order. */
    fun days(calendar: LocalCalendar): List<Double> {
        val days = mutableListOf<Double>()
        var day = firstSeconds
        while (day <= lastSeconds) {
            days += day
            val next = calendar.addingDays(1, day)
            if (next <= day) break
            day = next
        }
        return days
    }

    /** Whether [atSeconds] falls on one of the range's days. */
    fun contains(atSeconds: Double, calendar: LocalCalendar): Boolean {
        val day = calendar.startOfDay(atSeconds)
        return day >= firstSeconds && day <= lastSeconds
    }

    companion object {
        /** The [count] days ending with the one that holds [endingOnSeconds]. */
        fun last(count: Int, endingOnSeconds: Double, calendar: LocalCalendar): DateRange {
            val last = calendar.startOfDay(endingOnSeconds)
            return DateRange(calendar.addingDays(-(maxOf(count, 1) - 1), last), last, calendar)
        }
    }
}
