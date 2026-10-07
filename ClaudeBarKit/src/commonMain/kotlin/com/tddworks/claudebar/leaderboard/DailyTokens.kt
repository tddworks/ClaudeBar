package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.quotas.DailyUsageStat

/**
 * One provider's tokens for one local calendar day on this Mac — a line on the tally sheet, and
 * everything about a day that leaves the Mac. Cost, sessions, working time, models and paths
 * can't be expressed in it.
 */
public data class DailyTokens(
    val provider: String,
    /** The member's own date, `yyyy-MM-dd`. */
    val day: String,
    val input: Long,
    val output: Long,
    val cacheWrite: Long,
    val cacheRead: Long,
    /** Tokens a log keeps only as a sum, without saying which kind they were. */
    val unsplit: Long,
) {
    /** Every token the day holds — what the board ranks by. */
    val total: Long get() = input + output + cacheWrite + cacheRead + unsplit

    /** The same day with another login's tokens added. */
    fun adding(other: DailyTokens) = DailyTokens(
        provider, day, input + other.input, output + other.output,
        cacheWrite + other.cacheWrite, cacheRead + other.cacheRead, unsplit + other.unsplit,
    )

    companion object {
        /** A day of a login's usage history, kept to its token counts. */
        internal fun of(provider: String, stat: DailyUsageStat, calendar: MemberCalendar) = DailyTokens(
            provider = provider,
            day = calendar.day(stat.dateSeconds),
            input = stat.inputTokens,
            output = stat.outputTokens,
            cacheWrite = stat.cacheCreationTokens,
            cacheRead = stat.cacheReadTokens,
            unsplit = maxOf(0, stat.totalTokens - stat.inputTokens - stat.outputTokens),
        )

        /**
         * The days of `providers` in `logins`: each provider's logins added up per day, days
         * without tokens left out, oldest first. What an upload sends and what its preview shows
         * are both this.
         */
        internal fun summed(logins: List<LoginDays>, providers: Set<String>, calendar: MemberCalendar): List<DailyTokens> {
            val byDay = mutableMapOf<String, DailyTokens>()
            for (login in logins) {
                if (login.providerId !in providers) continue
                for (stat in login.days) {
                    val tokens = of(login.providerId, stat, calendar)
                    val key = tokens.provider + "|" + tokens.day
                    byDay[key] = byDay[key]?.adding(tokens) ?: tokens
                }
            }
            return byDay.values.filter { it.total > 0 }.sortedWith(compareBy({ it.day }, { it.provider }))
        }
    }
}

/** What one login on this Mac used, day by day. */
internal data class LoginDays(val providerId: String, val days: List<DailyUsageStat>)

/** This Mac's token logs: which providers have them, and what each login used. */
internal interface TokenLogs {
    /** Providers whose logins read daily tokens from logs — the only ones that can be shared. */
    val providersWithLogs: Set<String>

    suspend fun days(range: DayRange): List<LoginDays>
}
