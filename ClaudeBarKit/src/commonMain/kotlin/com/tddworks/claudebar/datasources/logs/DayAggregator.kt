package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.quotas.DailyUsageStat

/** Records into days: each record on the local day its own time falls in, priced, with working sessions split by `sessionGap`. */
internal object DayAggregator {
    /**
     * One stat per day of [range], every date present.
     * @param freeOnSeconds the day an unpriced model costs nothing — the day that holds now, when the route is local.
     */
    fun days(
        records: List<LogRecord>,
        range: DateRange,
        calendar: LocalCalendar,
        sessionGap: Double?,
        prices: PriceList?,
        freeOnSeconds: Double?,
    ): List<DailyUsageStat> {
        val byDay = records.filter { range.contains(it.atSeconds, calendar) }.groupBy { calendar.startOfDay(it.atSeconds) }
        return range.days(calendar).map { day ->
            stat(byDay[day].orEmpty(), day, sessionGap, prices, servedLocally = day == freeOnSeconds)
        }
    }

    fun stat(records: List<LogRecord>, daySeconds: Double, sessionGap: Double?, prices: PriceList?, servedLocally: Boolean): DailyUsageStat {
        if (records.isEmpty()) return DailyUsageStat.empty(daySeconds)
        var cost = NanoAmount.ZERO
        var savings = NanoAmount.ZERO
        for (record in records) {
            val own = record.cost
            if (own != null) {
                cost += own
            } else if (prices != null) {
                cost += prices.cost(record, servedLocally)
                savings += prices.savings(record, servedLocally)
            }
        }
        val (workingTime, sessions) = sessionsAndTime(records, sessionGap)
        return DailyUsageStat(
            dateSeconds = daySeconds,
            totalCostNanos = cost.rounded(),
            totalTokens = records.sumOf { it.tokens },
            workingTime = workingTime,
            sessionCount = sessions,
            inputTokens = records.sumOf { it.input },
            outputTokens = records.sumOf { it.output },
            cacheCreationTokens = records.sumOf { it.cacheWrite },
            cacheReadTokens = records.sumOf { it.cacheRead },
            cachedSavingsNanos = savings.rounded(),
        )
    }

    /**
     * Working time from first to last record of each session, a pause longer than [gap]
     * starting the next. Without a gap each record is a session and no working time is known.
     */
    private fun sessionsAndTime(records: List<LogRecord>, gap: Double?): Pair<Double, Long> {
        if (gap == null) return 0.0 to records.size.toLong()
        val times = records.map { it.atSeconds }.sorted()
        var workingTime = 0.0
        var sessions = 1L
        var start = times[0]
        var last = times[0]
        for (time in times.drop(1)) {
            if (time - last > gap) {
                workingTime += last - start
                start = time
                sessions += 1
            }
            last = time
        }
        workingTime += last - start
        return workingTime to sessions
    }
}
