package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.QuotaDuration
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import platform.Foundation.NSDate
import platform.Foundation.timeIntervalSince1970
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Kimi CLI /usage. */
class KimiCLIDefinitionParsingTest {
    private companion object {
        val fullOutput = """
        ╭─────────────────────────────── API Usage ───────────────────────────────╮
        │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
        │  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
        ╰─────────────────────────────────────────────────────────────────────────╯
        """.trimIndent()

        val partialUsageOutput = """
        ╭─────────────────────────────── API Usage ───────────────────────────────╮
        │  Weekly limit  ━━━━━━━━━━━━━━░░░░░░  75% left  (resets in 5d 12h 30m)   │
        │  5h limit      ━━━━━━━░░░░░░░░░░░░░  30% left  (resets in 2h 10m)       │
        ╰─────────────────────────────────────────────────────────────────────────╯
        """.trimIndent()

        val weeklyOnlyOutput = """
        ╭─────────────────────────────── API Usage ───────────────────────────────╮
        │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
        ╰─────────────────────────────────────────────────────────────────────────╯
        """.trimIndent()

        /** Real CLI output has no progress bar characters — just whitespace. */
        val noProgressBarOutput = """
        ╭─────────────────────────────── API Usage ───────────────────────────────╮
        │  Weekly limit                        100% left  (resets in 6d 22h 55m)  │
        │  5h limit                            100% left  (resets in 3h 55m)      │
        ╰─────────────────────────────────────────────────────────────────────────╯
        """.trimIndent()

        /** kimi CLI >= 0.36 reports "% used" without parentheses around the reset text. */
        val usedFormatOutput = """
          ╭ Usage ───────────────────────────────────────────────────────────╮
          │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
          │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
          ╰──────────────────────────────────────────────────────────────────╯
        """.trimIndent()

        /** The TUI redraws the usage panel, emitting each quota line more than once. */
        val redrawnOutput = """
        │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
        │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
        │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
        │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
        """.trimIndent()

        /** kimi CLI 2.x: Session usage / Context window sections, and a "Monthly limit" plan quota. Captured from 2.1.1. */
        val cli2xOutput = """
          ╭ Usage ────────────────────────────────────────────────────────────────╮
          │ Session usage                                                         │
          │   No token usage recorded yet.                                        │
          │                                                                       │
          │ Context window                                                        │
          │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                              │
          │                                                                       │
          │ Plan usage                                                            │
          │   5h limit       ░░░░░░░░░░░░░░░░░░░░  0% used  resets in 2h 41m      │
          │   Monthly limit  ░░░░░░░░░░░░░░░░░░░░  2% used  resets in 24d 16h 42m │
          │                  kimi 2% · code 0%                                    │
          ╰───────────────────────────────────────────────────────────────────────╯
        """.trimIndent()
    }

    private fun now() = NSDate().timeIntervalSince1970

    // Full output

    @Test
    fun `should show two quotas when the CLI prints a weekly and a 5-hour limit`() {
        val snapshot = KimiDefinitionFixtures.cli(fullOutput)

        assertEquals("kimi", snapshot.providerId)
        assertEquals(2, snapshot.quotas.size)
    }

    @Test
    fun `should show the weekly quota full when the CLI prints 100 percent left`() {
        assertEquals(100.0, assertNotNull(KimiDefinitionFixtures.cli(fullOutput).quota(QuotaType.Weekly)).percentRemaining)
    }

    @Test
    fun `should show the session full when the CLI prints 100 percent left on the 5-hour limit`() {
        assertEquals(100.0, assertNotNull(KimiDefinitionFixtures.cli(fullOutput).quota(QuotaType.Session)).percentRemaining)
    }

    // Partial usage

    @Test
    fun `should show 75 percent of the weekly quota left when the CLI prints 75 percent left`() {
        assertEquals(75.0, assertNotNull(KimiDefinitionFixtures.cli(partialUsageOutput).quota(QuotaType.Weekly)).percentRemaining)
    }

    @Test
    fun `should show 30 percent of the session left when the CLI prints 30 percent left`() {
        assertEquals(30.0, assertNotNull(KimiDefinitionFixtures.cli(partialUsageOutput).quota(QuotaType.Session)).percentRemaining)
    }

    // Weekly only

    @Test
    fun `should show only the weekly quota when the CLI prints no 5-hour limit`() {
        val snapshot = KimiDefinitionFixtures.cli(weeklyOnlyOutput)

        assertEquals(1, snapshot.quotas.size)
        assertNotNull(snapshot.quota(QuotaType.Weekly))
        assertNull(snapshot.quota(QuotaType.Session))
    }

    // No progress bar (real CLI output)

    @Test
    fun `should show both quotas when the CLI prints no progress bars`() {
        val snapshot = KimiDefinitionFixtures.cli(noProgressBarOutput)

        assertEquals(2, snapshot.quotas.size)
        assertEquals(100.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(100.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    // Used format (kimi CLI >= 0.36)

    @Test
    fun `should show what is left when the CLI prints the percent used`() {
        val snapshot = KimiDefinitionFixtures.cli(usedFormatOutput)

        assertEquals(2, snapshot.quotas.size)
        assertEquals(10.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(88.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should show when each quota resets when the CLI prints the reset without parentheses`() {
        val snapshot = KimiDefinitionFixtures.cli(usedFormatOutput)

        assertEquals("Resets in 35m", snapshot.quota(QuotaType.Weekly)?.resetText)
        assertEquals("Resets in 3h 35m", snapshot.quota(QuotaType.Session)?.resetText)
    }

    @Test
    fun `should reset the session in 3h 35m when the CLI prints the percent used and resets in 3h 35m`() {
        val now = now()
        val resetsAt = assertNotNull(KimiDefinitionFixtures.cli(usedFormatOutput).quota(QuotaType.Session)?.resetsAtSeconds)
        // 3h 35m = 12900s — allow 60s tolerance
        val diff = resetsAt - now
        assertTrue(diff > 12840)
        assertTrue(diff < 12960)
    }

    @Test
    fun `should show nothing left when the CLI prints 100 percent used`() {
        val depleted = "│   Weekly limit  ████████████████████  100% used  resets in 35m    │"

        assertEquals(0.0, KimiDefinitionFixtures.cli(depleted).quota(QuotaType.Weekly)?.percentRemaining)
    }

    // Redrawn panels

    @Test
    fun `should show each quota once when the CLI redraws the usage panel`() {
        val snapshot = KimiDefinitionFixtures.cli(redrawnOutput)

        assertEquals(2, snapshot.quotas.size)
        assertEquals(10.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(88.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
    }

    // CLI 2.x layout (Monthly plan quota)

    @Test
    fun `should show the session and the monthly quota when CLI 2x prints its plan usage`() {
        val snapshot = KimiDefinitionFixtures.cli(cli2xOutput)

        assertEquals(2, snapshot.quotas.size)
        assertEquals(100.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(98.0, snapshot.quota(QuotaType.TimeLimit("Monthly"))?.percentRemaining)
    }

    @Test
    fun `should show no quota for the context window or the per-model split when CLI 2x prints them`() {
        val snapshot = KimiDefinitionFixtures.cli(cli2xOutput)

        // "Context window … 0%  (0 / 1M)" and "kimi 2% · code 0%" must not become quotas
        assertEquals(2, snapshot.quotas.size)
        assertFalse(snapshot.quotas.any { it.quotaType == QuotaType.Weekly })
    }

    @Test
    fun `should show when the session and the monthly quota reset when CLI 2x prints them`() {
        val snapshot = KimiDefinitionFixtures.cli(cli2xOutput)

        assertEquals("Resets in 2h 41m", snapshot.quota(QuotaType.Session)?.resetText)
        assertEquals("Resets in 24d 16h 42m", snapshot.quota(QuotaType.TimeLimit("Monthly"))?.resetText)
    }

    @Test
    fun `should treat the monthly quota as a 30-day window when CLI 2x prints a monthly limit`() {
        val monthly = KimiDefinitionFixtures.cli(cli2xOutput).quota(QuotaType.TimeLimit("Monthly"))

        assertEquals(QuotaDuration.Days(30), monthly?.quotaType?.conventionalWindow)
    }

    // Reset time

    @Test
    fun `should reset the weekly quota in 6d 23h 22m when the CLI says so`() {
        val now = now()
        val resetsAt = assertNotNull(KimiDefinitionFixtures.cli(fullOutput).quota(QuotaType.Weekly)?.resetsAtSeconds)
        // 6d 23h 22m = 602520s — allow 60s tolerance
        val diff = resetsAt - now
        assertTrue(diff > 602460)
        assertTrue(diff < 602580)
    }

    @Test
    fun `should reset the session in 4h 22m when the CLI says so`() {
        val now = now()
        val resetsAt = assertNotNull(KimiDefinitionFixtures.cli(fullOutput).quota(QuotaType.Session)?.resetsAtSeconds)
        // 4h 22m ≈ 15720s — allow 60s tolerance
        val diff = resetsAt - now
        assertTrue(diff > 15660)
        assertTrue(diff < 15780)
    }

    @Test
    fun `should show the weekly reset as the CLI prints it`() {
        assertEquals("Resets in 6d 23h 22m", KimiDefinitionFixtures.cli(fullOutput).quota(QuotaType.Weekly)?.resetText)
    }

    // Reset duration

    @Test
    fun `should reset in days hours and minutes when the CLI gives all three`() {
        val now = now()
        val date = assertNotNull(KimiDefinitionFixtures.reset("6d 23h 22m"))
        assertTrue(abs(date - now - (6.0 * 86400 + 23.0 * 3600 + 22.0 * 60)) < 2)
    }

    @Test
    fun `should reset in hours and minutes when the CLI gives no days`() {
        val now = now()
        val date = assertNotNull(KimiDefinitionFixtures.reset("4h 22m"))
        assertTrue(abs(date - now - (4.0 * 3600 + 22.0 * 60)) < 2)
    }

    @Test
    fun `should reset in minutes when the CLI gives only minutes`() {
        val now = now()
        val date = assertNotNull(KimiDefinitionFixtures.reset("30m"))
        assertTrue(abs(date - now - 1800) < 2)
    }

    @Test
    fun `should reset in seconds when the CLI gives only seconds`() {
        val now = now()
        val date = assertNotNull(KimiDefinitionFixtures.reset("45s"))
        assertTrue(abs(date - now - 45) < 2)
    }

    @Test
    fun `should show a reset time when the session resets within seconds`() {
        val secondsReset = "│   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 45s │"
        val session = KimiDefinitionFixtures.cli(secondsReset).quota(QuotaType.Session)

        assertEquals(88.0, session?.percentRemaining)
        assertEquals("Resets in 45s", session?.resetText)
        assertNotNull(session?.resetsAtSeconds)
    }

    @Test
    fun `should have no reset time when the CLI gives no reset`() {
        assertNull(KimiDefinitionFixtures.reset(""))
    }

    // Errors

    @Test
    fun `should fail to read usage when the CLI prints nothing`() {
        assertFailsWith<UsageError> { KimiDefinitionFixtures.cli("") }
    }

    @Test
    fun `should fail to read usage when the CLI prints no usage panel`() {
        assertFailsWith<UsageError> { KimiDefinitionFixtures.cli("This is not a valid usage output") }
    }

    @Test
    fun `should fail to read usage when the CLI prints a limit with no percentage`() {
        val noPercent = """
        ╭──── API Usage ────╮
        │  Weekly limit  ━━━━━━━━━━━  no data  │
        ╰──────────────────╯
        """.trimIndent()

        assertFailsWith<UsageError> { KimiDefinitionFixtures.cli(noPercent) }
    }

    // Provider id

    @Test
    fun `should report the usage as Kimi's`() {
        assertEquals("kimi", KimiDefinitionFixtures.cli(fullOutput).providerId)
    }
}

/** What `kimi` prints for /usage when it isn't signed in (captured live). */
class KimiCLISignedOutTest {
    @Test
    fun `should ask the person to sign in and not show "no quota data" when the CLI is signed out`() {
        val screen = """
        hanrenwei@Probe💫 /usage
        Authorization failed. Please check your API key.
        """.trimIndent()

        val error = assertFailsWith<UsageError> { KimiDefinitionFixtures.cli(screen) }
        assertEquals(UsageError.SessionExpired("Run `kimi` and sign in with /login."), error)
    }
}
