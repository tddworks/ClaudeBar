package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.DateRange
import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.quotas.DailyUsageReport
import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.coroutines.flow.StateFlow

/**
 * *TODAY'S USAGE* — what one login used, day by day, read from its tool's own logs on this
 * Mac. Not a meter: nothing is left or judged, and the monitor never refreshes it; it is read
 * when the popover opens. The login owns it, as `account.usageHistory` (CANONICAL §2.1); how the
 * days are extracted is its provider's `usageHistory`, run as a [UsageLog].
 */
internal class UsageHistory(
    private val log: UsageLog,
    /** Where closed days are kept; without one every read goes to the logs. */
    private val ledger: DayLedger? = null,
    /** The app this history counts, when it isn't the login's own tool — another app on this Mac that uses the same plan. */
    val label: String? = null,
    /** Other apps on this Mac that use the same plan, each its own history: shown under its own name, never added to this one's days. */
    val otherApps: List<UsageHistory> = emptyList(),
) {
    /**
     * A login's history as its definition says, with one history per other app — each its own
     * log and, under `ledger("<login>/<label>")`, its own kept days.
     */
    constructor(
        definition: UsageLog.Definition,
        login: String,
        log: (UsageLog.Definition) -> UsageLog,
        ledger: (String) -> DayLedger? = { null },
    ) : this(
        log = log(definition),
        ledger = ledger(login),
        otherApps = (definition.otherApps ?: emptyList()).map { app ->
            UsageHistory(log = log(app.definition), ledger = ledger("$login/${app.label}"), label = app.label)
        },
    )

    private data class Read(val report: DailyUsageReport? = null, val lastThirtyDays: List<DailyUsageStat> = emptyList())

    private val state = ObservableState(Read())

    /** Bumped after every read. */
    val revision: StateFlow<Long> get() = state.revision

    /** Today's and yesterday's usage, once read and when either holds any. */
    val report: DailyUsageReport? get() = state.current.report

    /** *DAILY USAGE — LAST 30 DAYS*: the thirty days ending today, oldest first, once read and when any of them holds usage. */
    val lastThirtyDays: List<DailyUsageStat> get() = state.current.lastThirtyDays

    /** Whether a day's cost means anything; without it only tokens do. */
    val knowsCost: Boolean get() = log.knowsCost

    /** The other apps used today or yesterday — the ones with a card. */
    val usedOtherApps: List<UsageHistory> get() = otherApps.filter { it.report != null }

    /** Whether there is anything to show — this login's days or another app's. */
    val hasUsage: Boolean get() = report != null || usedOtherApps.isNotEmpty()

    /**
     * One day per date of [range], every date present. Closed days come from the ledger; the
     * logs are read only from the first day the ledger doesn't hold.
     */
    suspend fun days(range: DateRange): List<DailyUsageStat> {
        val ledger = ledger ?: return log.days(range)
        val calendar = log.calendar
        val now = log.currentTimeSeconds
        val kept = ledger.days(log.fingerprint)
        val dates = range.days(calendar)
        val firstMissing = dates.firstOrNull { day -> !DayLedger.isClosed(day, now, calendar) || kept[DayLedger.name(day)] == null }
            ?: return dates.mapNotNull { kept[DayLedger.name(it)] }

        val read = log.days(DateRange(firstMissing, range.lastSeconds, calendar))
        val closed = read.filter { DayLedger.isClosed(it.dateSeconds, now, calendar) }.associateBy { DayLedger.name(it.dateSeconds) }
        ledger.keep(closed, log.fingerprint)

        val before = dates.takeWhile { it < firstMissing }.mapNotNull { kept[DayLedger.name(it)] }
        return before + read
    }

    /**
     * Reads the logs again: today against yesterday first, for the cards, then the last thirty
     * days, for the chart — closed days from the ledger. Days with nothing are kept as none.
     */
    suspend fun read() {
        for (app in otherApps) app.read()
        val days = days(DateRange.last(2, log.currentTimeSeconds, log.calendar))
        if (days.size != 2) return
        val report = DailyUsageReport(today = days[1], previous = days[0])
        state.update { it.copy(report = if (report.today.isEmpty && report.previous.isEmpty) null else report) }

        val month = days(DateRange.last(30, log.currentTimeSeconds, log.calendar))
        state.update { it.copy(lastThirtyDays = if (month.all { day -> day.isEmpty }) emptyList() else month) }
    }
}
