package com.tddworks.claudebar.datasources.mapping

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.time.LocalDateTime
import java.time.ZoneId

/** `humanDate(text)` — reset times as CLIs print them, on a fixed clock so every expectation is exact. */
class HumanDateTest {
    /** 2026-06-15 12:00:00 UTC. */
    private val now = 1_781_524_800.0

    private fun parse(text: String, now: Double = this.now) = HumanDate.parse(text, now)

    private fun date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, zone: String = "UTC"): Double =
        LocalDateTime.of(year, month, day, hour, minute).atZone(ZoneId.of(zone)).toEpochSecond().toDouble()

    /** A wall-clock time in the zone the app runs in, for texts without a zone. */
    private fun local(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Double =
        LocalDateTime.of(year, month, day, hour, minute).atZone(ZoneId.systemDefault()).toEpochSecond().toDouble()

    // Relative durations

    @Test
    fun `should reset after the days, hours and minutes the CLI counts down`() {
        assertEquals(now + 2 * 86400, parse("resets in 2d"))
        assertEquals(now + 2 * 3600 + 15 * 60, parse("resets in 2h 15m"))
        assertEquals(now + 30 * 60, parse("30m"))
        assertEquals(now + 7200, parse("in 2h"))
    }

    @Test
    fun `should reset after a countdown with its units spelled out`() {
        assertEquals(now + 2 * 3600 + 5 * 60, parse("Resets in 2 hours 5 min"))
        assertEquals(now + 86400, parse("1 day"))
        assertEquals(now + 600, parse("10 minutes"))
    }

    @Test
    fun `should know no reset time when the text holds none`() {
        assertNull(parse(""))
        assertNull(parse("no time here"))
    }

    // Absolute times

    @Test
    fun `should reset later today at a time the CLI gives in its time zone`() {
        // 8am in New York: 4:59pm is still ahead today.
        assertEquals(date(2026, 6, 15, 16, 59, "America/New_York"), parse("Resets 4:59pm (America/New_York)"))
    }

    @Test
    fun `should reset tomorrow when the time given has already passed today`() {
        // 6pm in New York: 4:59pm has gone, so tomorrow's.
        val evening = date(2026, 6, 15, 18, 0, "America/New_York")

        assertEquals(date(2026, 6, 16, 16, 59, "America/New_York"), parse("Resets 4:59pm (America/New_York)", now = evening))
    }

    @Test
    fun `should reset at an hour the CLI gives without minutes in its time zone`() {
        // 8pm in Shanghai: 3pm has gone, so tomorrow's.
        assertEquals(date(2026, 6, 16, 15, 0, "Asia/Shanghai"), parse("Resets 3pm (Asia/Shanghai)"))
    }

    @Test
    fun `should reset on the day and time the CLI gives in its time zone`() {
        assertEquals(date(2026, 12, 25, 4, 59, "Asia/Shanghai"), parse("Resets Dec 25 at 4:59am (Asia/Shanghai)"))
    }

    @Test
    fun `should reset next year when the day the CLI gives has passed this year`() {
        // January 15 has passed this year, so next year's.
        assertEquals(date(2027, 1, 15, 15, 30, "America/Los_Angeles"), parse("Resets Jan 15, 3:30pm (America/Los_Angeles)"))
    }

    @Test
    fun `should reset on the day and hour the CLI gives in its time zone`() {
        assertEquals(date(2027, 2, 12, 16, 0, "Asia/Shanghai"), parse("Resets Feb 12 at 4pm (Asia/Shanghai)"))
        assertEquals(date(2026, 7, 2, 4, 59, "America/Chicago"), parse("Resets Jul 2 at 4:59am (America/Chicago)"))
    }

    @Test
    fun `should reset at the day and time the CLI gives in this Mac's time zone when it names none`() {
        assertEquals(local(2027, 1, 15, 15, 30), parse("Resets Jan 15, 3:30pm"))
    }

    @Test
    fun `should reset on the full date the CLI gives in its time zone`() {
        assertEquals(date(2027, 1, 1, 0, 0, "America/New_York"), parse("Resets Jan 1, 2027 (America/New_York)"))
    }

    @Test
    fun `should keep a reset date with a year even when it has passed`() {
        assertEquals(date(2026, 1, 1, 0, 0, "America/New_York"), parse("Resets Jan 1, 2026 (America/New_York)"))
    }

    @Test
    fun `should reset at the start of the day the CLI gives when it names no time`() {
        assertEquals(local(2026, 12, 28), parse("Resets Dec 28"))
    }

    @Test
    fun `should reset at different moments for the same clock time in different time zones`() {
        val eastern = parse("Resets 4:59pm (America/New_York)")
        val shanghai = parse("Resets 4:59pm (Asia/Shanghai)")

        assertEquals(date(2026, 6, 15, 20, 59), eastern)
        assertEquals(date(2026, 6, 16, 8, 59), shanghai)
        assertNotEquals(eastern, shanghai, "Same wall-clock time in different timezones should produce different instants")
    }

    // Text around the time

    @Test
    fun `should find the reset time when a percentage shares its line`() {
        assertEquals(date(2026, 6, 15, 15, 0, "Europe/Amsterdam"), parse("Resets 3pm (Europe/Amsterdam)                      27% used"))
    }

    @Test
    fun `should use the last reset time on a line that holds more than one`() {
        assertEquals(date(2026, 1, 1, 0, 0, "America/New_York"), parse("$5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)"))
        assertEquals(
            date(2026, 6, 15, 16, 59, "America/New_York"),
            parse("Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)"),
        )
    }
}
