package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.process.TerminalRenderer
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import java.math.BigDecimal
import kotlin.math.abs

/**
 * Claude Code's `/cost` screen read by `claude.json`'s `cliCost` data source: drawn by the
 * terminal emulator, then `claude-cost-screen.js`. The fixtures are the Swift suite's, verbatim.
 */
class ClaudeCostScreenTest {

    private val costCommandOutput = """
        Total cost:            ${'$'}0.55
        Total duration (API):  6m 19.7s
        Total duration (wall): 6h 33m 10.2s
        Total code changes:    0 lines added, 0 lines removed
    """.trimIndent()

    private val costCommandOutputLargeCost = """
        Total cost:            ${'$'}1,234.56
        Total duration (API):  2h 30m 45.5s
        Total duration (wall): 48h 15m 30.2s
        Total code changes:    1500 lines added, 200 lines removed
    """.trimIndent()

    private fun dollars(amount: String): Long = BigDecimal(amount).movePointRight(9).longValueExact()

    // /cost Command Parsing

    @Test
    fun `should show the session's total cost, with no budget and no quotas, on an API plan`() {
        val snapshot = read(costCommandOutput)

        assertEquals(AccountTier.ClaudeApi, snapshot.accountTier)
        assertEquals(dollars("0.55"), snapshot.costUsage?.totalCostNanos)
        assertNull(snapshot.costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.API_COST, snapshot.costUsage?.kind)
        assertTrue(snapshot.quotas.isEmpty())
    }

    @Test
    fun `should show the time spent in the API, 6m 19_7s, from the cost screen`() {
        val snapshot = read(costCommandOutput)

        // 6m 19.7s = 6*60 + 19.7 = 379.7 seconds
        assertTrue((snapshot.costUsage?.apiDuration ?: 0.0) > 379)
        assertTrue((snapshot.costUsage?.apiDuration ?: 0.0) < 380)
    }

    @Test
    fun `should show a cost over a thousand dollars written with commas`() {
        assertEquals(dollars("1234.56"), read(costCommandOutputLargeCost).costUsage?.totalCostNanos)
    }

    @ParameterizedTest
    @MethodSource("costLines")
    fun `should show the total cost however the cost line is spaced or written`(line: String, cost: String) {
        assertEquals(dollars(cost), read(line).costUsage?.totalCostNanos)
    }

    @Test
    fun `should show the API time when the screen holds only the cost and the duration`() {
        val snapshot = read("Total cost: \$0.55\nTotal duration (API):  6m 19.7s")

        // 6*60 + 19.7 = 379.7
        assertTrue((snapshot.costUsage?.apiDuration ?: 0.0) > 379)
        assertTrue((snapshot.costUsage?.apiDuration ?: 0.0) < 380)
    }

    @Test
    fun `should show no API time when the cost screen has none`() {
        assertEquals(0.0, read("Total cost: \$0.55").costUsage?.apiDuration)
    }

    @ParameterizedTest
    @MethodSource("durations")
    fun `should show the API time in seconds however its hours, minutes and seconds are written`(duration: String, seconds: Double) {
        val snapshot = read("Total cost: \$0.55\nTotal duration (API):  $duration")

        assertTrue(abs((snapshot.costUsage?.apiDuration ?: -1.0) - seconds) < 0.001, "got ${snapshot.costUsage?.apiDuration}")
    }

    // /cost Screens That Are Not Cost Readings (issue #317)

    /**
     * A `/cost` screen that reports a failure is not a cost of zero. A throttled CLI still paints
     * the panel, `$0.0000` reads off it, and the data source would *succeed* with a cost of nothing (#317).
     */
    @Test
    fun `should report a rate limit rather than a cost of zero (#317)`() {
        val rateLimited = costCommandOutput + "\nError: Usage endpoint is rate limited. Please try again in a moment."

        assertEquals(UsageError.ExecutionFailed("Rate limited - too many requests"), assertThrows(UsageError::class.java) { read(rateLimited) })
    }

    @Test
    fun `should ask to sign in rather than show a cost of zero when the CLI is logged out`() {
        val loggedOut = costCommandOutput + "\nInvalid API key · Please log in with /login"

        assertEquals(UsageError.AuthenticationRequired, assertThrows(UsageError::class.java) { read(loggedOut) })
    }

    /** A capture that ended before the cost panel was painted at all has no `Total cost` row, and says so instead of answering `$0.00`. */
    @Test
    fun `should fail to read rather than show a cost of zero when the cost panel was never painted`() {
        val beforeThePanel = """
            Claude Code v2.1.274
            Opus 5 (1M context) with high effort · API Usage Billing
            ~/Library/Application Support/ClaudeBar/Probe
             Esc to cancel
        """.trimIndent()

        assertEquals(UsageError.ParseFailed("Could not find total cost"), assertThrows(UsageError::class.java) { read(beforeThePanel) })
    }

    /** The panel is painted in full during boot, so `$0.0000` off it is the probe session's own spend, not a misread. */
    @Test
    fun `should show a cost of zero when the fully painted panel is of an empty session`() {
        val panelOnly = """
            Claude Code v2.1.274
            Opus 5 (1M context) with high effort · API Usage Billing
              Session
                Total cost:            ${'$'}0.0000
                Total duration (API):  0s
                Total duration (wall): 1s
                Total code changes:  0 lines added, 0 lines removed
                Usage: 0 input, 0 output, 0 cache read, 0 cache write
              Esc to cancel
        """.trimIndent()

        val snapshot = read(panelOnly)
        assertEquals(0L, snapshot.costUsage?.totalCostNanos)
        assertEquals(AccountTier.ClaudeApi, snapshot.accountTier)
    }

    // Helper

    /** The screen as the `cliCost` data source reads it: rendered, then scripted. */
    private fun read(screen: String): UsageSnapshot {
        val claude = ClaudeHarness()
        try {
            return claude.readCostScreen(TerminalRenderer(160, 50).render(screen))
        } finally {
            claude.cleanUp()
        }
    }

    companion object {
        @JvmStatic
        fun costLines() = listOf(
            Arguments.of("Total cost:            \$0.55", "0.55"),
            Arguments.of("Total cost: \$1,234.56", "1234.56"),
            Arguments.of("Total cost:   0.00", "0.00"),
        )

        @JvmStatic
        fun durations() = listOf(
            Arguments.of("2h 30m", 9000.0),
            Arguments.of("1h", 3600.0),
            Arguments.of("45s", 45.0),
            Arguments.of("2h 30m 45.5s", 9045.5),
            Arguments.of("6m 19.7s", 379.7),
        )
    }
}
