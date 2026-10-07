package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CLICompletionRuleTest {
    private val esc = "\u001B"
    private val rule = usageScreenRule

    /** What the usage screen paints within milliseconds of opening: the cost panel and a placeholder. */
    private val loadingScreen = """
        Claude Code v2.1.251
        Opus 5 (1M context) · Claude Max

          Settings  Status  Config  Usage  Stats

          Session
            Total cost:            ${'$'}0.0000
            Total duration (API):  0s
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write

            Loading usage data…

          Esc to cancel
    """.trimIndent()

    /** The same capture seconds later: cumulative, so the placeholder is still there. */
    private val loadedScreen = loadingScreen + "\n" + """

          Current session
            ▌                       1% used
            Resets 3:20pm (Asia/Shanghai)
    """.trimIndent()

    /**
     * The screen while the CLI still boots, `/usage` unsubmitted and the hooks running —
     * verbatim from #317, cursor escapes kept: every word run lands at its own column.
     */
    private val bootScreen = listOf(
        "$esc[1C$esc[1B▐▛███▛█$esc[12GClaude$esc[19GCode$esc[24Gv2.1.273",
        "$esc[1B▝▜██████▀$esc[12GOpus$esc[17G5$esc[19G(1M$esc[23Gcontext)$esc[32Gwith$esc[37Ghigh$esc[42Geffort$esc[49G·$esc[51GAPI$esc[55GUsage$esc[61GBilling",
        "$esc[2C$esc[1B▝▝$esc[6G▝▝$esc[12G~/Library/Application$esc[34GSupport/ClaudeBar/Probe",
        "$esc[3B❯$esc[3G/usage",
        "$esc[38B✢$esc[3GBurrowing…$esc[14G(running$esc[23GSessionStart$esc[36Ghooks…$esc[43G2/5$esc[47G·$esc[49G0s)",
        "$esc[142C$esc[1B●$esc[145Ghigh$esc[150G·$esc[152G/effort",
        "$esc[2C$esc[1B⏵⏵$esc[6Gauto$esc[11Gmode$esc[16Gon$esc[19G(shift+tab$esc[30Gto$esc[33Gcycle)$esc[40G·$esc[42Gesc$esc[46Gto$esc[49Ginterrupt$esc[59G·$esc[61G←$esc[63Gfor$esc[67Gagents",
        "$esc[2C$esc[1B Settings  Status   Config   Usage   Stats",
        "$esc[2B Session",
        "$esc Total cost:            ${'$'}0.0000",
        "$esc Total duration (API):  0s",
        "$esc Total duration (wall): 1s",
        "$esc Total code changes:  0 lines added, 0 lines removed",
        "$esc Usage: 0 input, 0 output, 0 cache read, 0 cache write",
        "$esc Esc$esc[8Gto$esc[11Gcancel",
    ).joinToString("\n")

    @Test
    fun `should keep waiting while Claude's usage screen shows only its loading placeholder`() {
        assertTrue(rule.isPending(loadingScreen))
    }

    @Test
    fun `should stop waiting once the quota bars arrive, even with the placeholder still on screen`() {
        assertFalse(rule.isPending(loadedScreen))
    }

    @Test
    fun `should keep waiting when the CLI hasn't reached the Usage tab, even with no placeholder (#317)`() {
        val costPanelOnly = """
            Opus 5 (1M context) · API Usage Billing
              Session
                Total cost:            ${'$'}0.0000
        """.trimIndent()

        assertTrue(rule.isPending(costPanelOnly))
    }

    @Test
    fun `should keep waiting while the CLI is still booting (#317)`() {
        assertTrue(rule.isPending(bootScreen))
    }

    @Test
    fun `should stop waiting when the quota bars are drawn in pieces across the screen`() {
        val split = "$esc[3C$esc[2BCurre$esc[10Gt$esc[12Gsession\n$esc[1B█████$esc[55G38%$esc[59Gused"

        assertFalse(rule.isPending(split))
    }

    @Test
    fun `should keep waiting when the loading placeholder is drawn in pieces across the screen`() {
        assertTrue(rule.isPending("$esc[3C$esc[2BLoading$esc[12Gusage$esc[18Gdata…"))
    }

    @Test
    fun `should not take a word that merely contains a section label as the label`() {
        val label = CLICompletionRule(listOf(CLICompletionRule.Marker.row("Current session")))

        assertFalse(label.isReady("myCurrent session here"))
        assertFalse(label.isReady("XCurrent sessionY"))
        assertFalse(label.isReady("Current sessions"))
        assertTrue(label.isReady("Current session"))
    }

    @Test
    fun `should keep waiting when a startup hook's text happens to mention the current session (#317)`() {
        val hookProse = "$esc[1B  $esc[5C$esc[6G$esc[25GSessionStart:startup says: # claude-mem status\n" +
            "$esc[1B    $esc[5CThis project has no memory yet. The current session will seed it; subsequent sessions will receive auto-injected context for relevant past work."
        val label = CLICompletionRule(listOf(CLICompletionRule.Marker.row("Current session")))

        assertFalse(label.isReady(hookProse))
        assertTrue(rule.isPending(hookProse))
    }

    @Test
    fun `should stop waiting when a percentage or rate-limit message shares its row with other text (#317)`() {
        val shared = """
                  Session
                    Total cost:            ${'$'}0.0000
                    Total duration (API):  0s
                    Usage:                 0 input, 0 output, 0 cache read, 0 cache write
                    27% used  Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)
        """.trimIndent()

        assertTrue(rule.isReady(shared))
        assertTrue(rule.isReady("Error: Output rate limited, retrying in 20s"))
    }

    @Test
    fun `should stop waiting when the percentage used is shown, wherever it sits on its row`() {
        val value = CLICompletionRule(listOf(CLICompletionRule.Marker("% used")))

        assertTrue(value.isReady("38% used"))
        assertTrue(value.isReady("  38% used\n"))
        assertTrue(value.isReady("38% used  Resets 4:59pm (America/New_York)"))
        assertTrue(value.isReady("Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)  27% used"))
    }

    @Test
    fun `should stop waiting on a section label only when it fills its own row`() {
        val label = CLICompletionRule(listOf(CLICompletionRule.Marker.row("Current session")))

        assertTrue(label.isReady("Current session\n  expires in 5m"))
        assertFalse(label.isReady("Current session  expires in 5m"))
        assertTrue(rule.isPending("Current session  expires in 5m"))
    }

    @Test
    fun `should stop waiting at once when the CLI shows a rate-limit error`() {
        val rateLimited = loadingScreen + "\nError: Usage endpoint is rate limited. Please try again in a moment."

        assertFalse(rule.isPending(rateLimited))
    }

    /** The settled `/cost` screen: one static panel, so its run needs no rule — and must not borrow this one. */
    private val settledCostScreen = """
        Claude Code v2.1.273
          Session
            Total cost:            ${'$'}3.5500
            Total duration (API):  6m 19.7s
            Total duration (wall): 6h 33m 10.2s
            Total code changes:    12 lines added, 3 lines removed
          Esc to cancel
    """.trimIndent()

    @Test
    fun `should keep waiting on a finished cost screen, which is why the cost run uses no such rule (#317)`() {
        assertTrue(rule.isPending(settledCostScreen))
    }

    @Test
    fun `should keep waiting on the boot screen even though it already shows a total cost (#317)`() {
        assertTrue(rule.isPending(bootScreen))
        assertTrue("Total cost" in bootScreen)
    }

    @Test
    fun `should recognise what ends the wait in any letter case, and nothing else`() {
        val done = CLICompletionRule(listOf(CLICompletionRule.Marker("done")))

        assertTrue(done.isPending("LOADING…"))
        assertFalse(done.isPending("LOADING… DONE"))
    }
}
