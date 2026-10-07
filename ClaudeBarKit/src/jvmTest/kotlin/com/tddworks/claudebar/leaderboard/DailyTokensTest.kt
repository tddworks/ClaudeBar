package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class DailyTokensTest {
    private val calendar = LeaderboardFixtures.calendar

    private fun stat(total: Long, input: Long = 0, output: Long = 0, cacheWrite: Long = 0, cacheRead: Long = 0) = DailyUsageStat(
        dateSeconds = LeaderboardFixtures.date(4, hour = 9), totalCostNanos = 12_000_000_000, totalTokens = total,
        workingTime = 3600.0, sessionCount = 3, inputTokens = input, outputTokens = output,
        cacheCreationTokens = cacheWrite, cacheReadTokens = cacheRead, cachedSavingsNanos = 4_000_000_000,
    )

    @Test
    fun `should share only a day's four token counts and its local date, never its cost or time`() {
        val tokens = DailyTokens.of("claude", stat(total = 150, input = 100, output = 50, cacheWrite = 20, cacheRead = 900), calendar)

        assertEquals(DailyTokens("claude", "2026-10-04", input = 100, output = 50, cacheWrite = 20, cacheRead = 900, unsplit = 0), tokens)
        assertEquals(1070L, tokens.total)
    }

    @Test
    fun `should share a log's sum as one count when the log keeps only the sum`() {
        val tokens = DailyTokens.of("mistral", stat(total = 5000), calendar)

        assertEquals(5000L, tokens.unsplit)
        assertEquals(5000L, tokens.total)
    }

    @Test
    fun `should add up two logins' days of one provider`() {
        val work = DailyTokens("claude", "2026-10-04", input = 1, output = 2, cacheWrite = 3, cacheRead = 4, unsplit = 5)
        val personal = DailyTokens("claude", "2026-10-04", input = 10, output = 20, cacheWrite = 30, cacheRead = 40, unsplit = 50)

        assertEquals(165L, work.adding(personal).total)
    }

    @Test
    fun `should share only the chosen providers, each one's logins added up per day`() {
        fun stat(input: Long) = DailyUsageStat(LeaderboardFixtures.date(4, hour = 9), 0, input, 0.0, 1, input, 0, 0, 0, 0)
        val days = DailyTokens.summed(
            listOf(
                LoginDays("claude", listOf(stat(10))),
                LoginDays("claude", listOf(stat(5))),
                LoginDays("codex", listOf(stat(99))),
            ),
            providers = setOf("claude"),
            calendar = calendar,
        )

        assertEquals(listOf(15L), days.map { it.input })
        assertEquals(listOf("claude"), days.map { it.provider })
    }

    @Test
    fun `should share each count under its own name and nothing more`() {
        val tokens = DailyTokens("codex", "2026-10-04", input = 1, output = 2, cacheWrite = 3, cacheRead = 4, unsplit = 0)

        val json = LeaderboardWire.encode(tokens).jsonObject

        assertEquals(setOf("provider", "day", "input", "output", "cacheWrite", "cacheRead", "unsplit"), json.keys)
    }
}
