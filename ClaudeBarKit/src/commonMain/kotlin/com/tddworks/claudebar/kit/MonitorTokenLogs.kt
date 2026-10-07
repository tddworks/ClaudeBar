package com.tddworks.claudebar.kit

import com.tddworks.claudebar.datasources.logs.DateRange
import com.tddworks.claudebar.datasources.logs.LocalCalendar
import com.tddworks.claudebar.datasources.logs.localCalendar
import com.tddworks.claudebar.leaderboard.DayRange
import com.tddworks.claudebar.leaderboard.LoginDays
import com.tddworks.claudebar.leaderboard.TokenLogs
import com.tddworks.claudebar.monitoring.QuotaMonitor

/** This Mac's token logs: every login whose provider reads usage history — Claude, Codex, Mistral and Oh My Pi today. */
internal class MonitorTokenLogs(
    private val monitor: QuotaMonitor,
    private val calendar: LocalCalendar = localCalendar(),
) : TokenLogs {
    private val logins get() = monitor.logins.mapNotNull { login -> login.usageHistory?.let { login.providerId to it } }

    override val providersWithLogs: Set<String> get() = logins.map { it.first }.toSet()

    override suspend fun days(range: DayRange): List<LoginDays> {
        val dates = DateRange(range.firstSeconds, range.lastSeconds, calendar)
        return logins.map { (providerId, history) -> LoginDays(providerId, history.days(dates)) }
    }
}
