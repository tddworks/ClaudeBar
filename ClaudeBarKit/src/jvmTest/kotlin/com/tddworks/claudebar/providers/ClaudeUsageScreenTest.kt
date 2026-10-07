package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.CostUsage
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.math.BigDecimal
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * Claude Code's `/usage` screen read by `claude.json`'s `cli` data source: drawn by the terminal
 * emulator (`"screen": "rendered"`), then `claude-usage-screen.js`, with the account from
 * `~/.claude.json`. The fixtures are the Swift suite's, verbatim.
 */
class ClaudeUsageScreenTest {

    // Sample CLI Output

    private val sampleClaudeOutput = """
        Claude Code v1.0.27

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Jan 15, 3:30pm (America/Los_Angeles)

        Current week (Opus)
        ████████████████████ 80% left
        Resets Jan 15, 3:30pm (America/Los_Angeles)

        Account: user@example.com
        Organization: Acme Corp
        Login method: Claude Max
    """.trimIndent()

    private val exhaustedQuotaOutput = """
        Claude Code v1.0.27

        Current session
        ░░░░░░░░░░░░░░░░░░░░ 0% left
        Resets in 30m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Jan 15, 3:30pm
    """.trimIndent()

    private val usedPercentOutput = """
        Current session
        ████████████████████ 25% used

        Current week (all models)
        ████████████░░░░░░░░ 60% used
    """.trimIndent()

    private val fableQuotaOutput = """
        Claude Code v2.1.198

        Current session
        ██████████░░░░░░░░░░ 23% used
        Resets 1:09am (America/Chicago)

        Current week (all models)
        ██░░░░░░░░░░░░░░░░░░ 10% used
        Resets Jul 2 at 4:59am (America/Chicago)

        Current week (Fable)
        ████░░░░░░░░░░░░░░░░ 17% used
        Resets Jul 2 at 5:59am (America/Chicago)
    """.trimIndent()

    /** 2026-06-15 12:00:00 UTC — a fixed clock for reset times. */
    private val now = 1_781_524_800.0

    private fun dollars(amount: String): Long = BigDecimal(amount).movePointRight(9).longValueExact()

    /** Writes `\u001B` where a fixture shows `⎋`. */
    private fun escaped(text: String) = text.replace("⎋", "\u001B")

    // Parsing Percentages

    @Test
    fun `should show a healthy session with 65% left when the screen prints percent left`() {
        val snapshot = read(sampleClaudeOutput)

        assertEquals(65.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(QuotaStatus.HEALTHY, snapshot.sessionQuota?.status)
    }

    @Test
    fun `should show the weekly window as a warning at 35% left`() {
        val snapshot = read(sampleClaudeOutput)

        assertEquals(35.0, snapshot.weeklyQuota?.percentRemaining)
        assertEquals(QuotaStatus.WARNING, snapshot.weeklyQuota?.status)
    }

    @Test
    fun `should show the Opus weekly window on its own`() {
        val opusQuota = read(sampleClaudeOutput).quota(QuotaType.ModelSpecific("opus"))

        assertEquals(80.0, opusQuota?.percentRemaining)
        assertEquals(QuotaStatus.HEALTHY, opusQuota?.status)
    }

    /** Claude Code 2.1.289's `/usage`: the session's cost and the plugin skill-listing footprint sit above the limits, and an advice section below. */
    private val costAndFootprintAboveTheLimitsOutput = """
        Settings  Status  Config  Usage  Stats

        Session

        Total cost:            $0.0000
        Total duration (API):  0s
        Total duration (wall): 1s
        Total code changes:    0 lines added, 0 lines removed
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write

        Plugin skill-listing footprint
        What each plugin's skill descriptions add to the system prompt (cached input after the first turn).

        feature-dev                 1 skill · ~26 tok/turn

        Total                       ~26 tok/turn

        Current session
        ██████████████░░░░░░░░░░░░░░░░░░░░░░░░░  37% used
        Resets 3:59pm (Asia/Shanghai)

        Current week (all models)
        ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  21% used
        Resets Oct 11 at 10:59am (Asia/Shanghai)

        Current week (Fable)
        ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0% used
        Resets Oct 11 at 11am (Asia/Shanghai)

        What's contributing to your limits usage?
        Approximate, based on local sessions on this machine — does not include other devices or claude.ai
    """.trimIndent()

    @Test
    fun `should read the limits when the session's cost and the plugin footprint sit above them`() {
        val snapshot = read(costAndFootprintAboveTheLimitsOutput, config = """{"oauthAccount":{"billingType":"stripe_subscription"}}""")

        assertEquals(63.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(79.0, snapshot.weeklyQuota?.percentRemaining)
        assertEquals(100.0, snapshot.quota(QuotaType.ModelSpecific("fable"))?.percentRemaining)
        assertTrue(snapshot.quota(QuotaType.ModelSpecific("fable"))?.resetText?.contains("11am") == true)
    }

    @Test
    fun `should show the Fable weekly window with its own reset time`() {
        val fableQuota = read(fableQuotaOutput).quota(QuotaType.ModelSpecific("fable"))

        // 17% used = 83% remaining, reset from the Fable section (not all-models)
        assertEquals(83.0, fableQuota?.percentRemaining)
        assertEquals(QuotaStatus.HEALTHY, fableQuota?.status)
        assertTrue(fableQuota?.resetText?.contains("5:59am") == true)
    }

    private val fableQuotaWithoutOwnResetOutput = """
        Current session
        ██████████░░░░░░░░░░ 23% used
        Resets 1:09am (America/Chicago)

        Current week (all models)
        ██░░░░░░░░░░░░░░░░░░ 10% used
        Resets Jul 2 at 4:59am (America/Chicago)

        Current week (Fable)
        ████░░░░░░░░░░░░░░░░ 17% used
    """.trimIndent()

    @Test
    fun `should give the Fable window the weekly reset when its section prints none`() {
        // inherits the all-models weekly reset
        val fableQuota = read(fableQuotaWithoutOwnResetOutput).quota(QuotaType.ModelSpecific("fable"))

        assertEquals(83.0, fableQuota?.percentRemaining)
        assertTrue(fableQuota?.resetText?.contains("4:59am") == true)
    }

    @Test
    fun `should show no Fable window when the screen has no Fable section`() {
        assertNull(read(sampleClaudeOutput).quota(QuotaType.ModelSpecific("fable")))
    }

    @Test
    fun `should show percent left when the screen prints percent used`() {
        val snapshot = read(usedPercentOutput)

        // 25% used = 75% left, 60% used = 40% left
        assertEquals(75.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(40.0, snapshot.weeklyQuota?.percentRemaining)
    }

    @Test
    fun `should show the session as depleted at 0% left`() {
        val snapshot = read(exhaustedQuotaOutput)

        assertEquals(0.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(QuotaStatus.DEPLETED, snapshot.sessionQuota?.status)
        assertEquals(true, snapshot.sessionQuota?.isDepleted)
    }

    // Account Info from ~/.claude.json

    @Test
    fun `should show the account email and organization from Claude Code's config`() {
        val claude = ClaudeHarness()
        try {
            claude.writeClaudeConfig(email = "user@example.com", displayName = "Acme Corp")

            val snapshot = claude.readRawUsageScreen(sampleClaudeOutput)

            assertEquals("user@example.com", snapshot.accountEmail)
            assertEquals("Acme Corp", snapshot.accountOrganization)
        } finally {
            claude.cleanUp()
        }
    }

    @Test
    fun `should show no account when there is no config, even though the screen prints one`() {
        // The screen prints "Account:" and "Organization:" rows; they are not read.
        val snapshot = read(sampleClaudeOutput)

        assertNull(snapshot.accountEmail)
        assertNull(snapshot.accountOrganization)
    }

    @Test
    fun `should show the signed-in email and display name`() {
        val snapshot = read(sampleClaudeOutput, config = """
            {
                "oauthAccount": {
                    "accountUuid": "abc-123",
                    "emailAddress": "user@example.com",
                    "organizationUuid": "org-456",
                    "displayName": "testuser",
                    "billingType": "stripe_subscription"
                }
            }
        """)

        assertEquals("user@example.com", snapshot.accountEmail)
        assertEquals("testuser", snapshot.accountOrganization)
    }

    @Test
    fun `should show only the email when the account has no display name`() {
        val snapshot = read(sampleClaudeOutput, config = """{ "oauthAccount": { "emailAddress": "user@example.com" } }""")

        assertEquals("user@example.com", snapshot.accountEmail)
        assertNull(snapshot.accountOrganization)
    }

    @Test
    fun `should show only the display name when the account has no email`() {
        val snapshot = read(sampleClaudeOutput, config = """{ "oauthAccount": { "displayName": "testuser" } }""")

        assertNull(snapshot.accountEmail)
        assertEquals("testuser", snapshot.accountOrganization)
    }

    @Test
    fun `should show no account when the config has no signed-in account`() {
        val snapshot = read(sampleClaudeOutput, config = """{ "numStartups": 100 }""")

        assertNull(snapshot.accountEmail)
        assertNull(snapshot.accountOrganization)
    }

    @Test
    fun `should show no account when the signed-in account has neither email nor name`() {
        val snapshot = read(sampleClaudeOutput, config = """{ "oauthAccount": { "accountUuid": "abc-123", "organizationUuid": "org-456" } }""")

        assertNull(snapshot.accountEmail)
        assertNull(snapshot.accountOrganization)
    }

    @Test
    fun `should still show the quotas, with no account, when the config is damaged`() {
        val snapshot = read(sampleClaudeOutput, config = "not valid json {{{")

        assertNull(snapshot.accountEmail)
        assertNull(snapshot.accountOrganization)
        assertEquals(65.0, snapshot.sessionQuota?.percentRemaining)
    }

    @Test
    fun `should say the CLI missed the subscription when a subscriber's screen shows API billing`() {
        assertEquals(UsageError.ExecutionFailed(subscriptionMisread), failure {
            read(apiBillingCostPanelOutput, config = """{ "oauthAccount": { "emailAddress": "user@example.com", "billingType": "apple_subscription" } }""")
        })
    }

    @Test
    fun `should say the CLI missed the subscription even when the subscriber's account has no name (#271)`() {
        // The billing type decides whether a `/usage` cost panel means "this is an API account"
        // or "the CLI could not see the subscription" (#271), so it is read on its own.
        assertEquals(UsageError.ExecutionFailed(subscriptionMisread), failure {
            read(apiBillingCostPanelOutput, config = """{ "oauthAccount": { "accountUuid": "abc-123", "billingType": "stripe_subscription" } }""")
        })
    }

    @Test
    fun `should fall back to session cost when the account names no billing type`() {
        assertEquals(UsageError.SubscriptionRequired, failure {
            read(apiBillingCostPanelOutput, config = """{ "oauthAccount": { "emailAddress": "user@example.com" } }""")
        })
    }

    // Error Detection

    private val trustPromptOutput = """
        Do you trust the files in this folder?
        /Users/test/project

        Yes, proceed (y)
        No, cancel (n)
    """.trimIndent()

    // New trust prompt format introduced in later Claude CLI versions
    private val newTrustPromptOutput = """
        Accessing workspace:

        /Users/testuser/Library/Application Support/ClaudeBar/Probe

        Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source project, or work from your team). If not, take a moment to review what's in this folder first.

        Claude Code'll be able to read, edit, and execute files here.

        ❯ 1. Yes, I trust this folder
          2. No, exit
    """.trimIndent()

    private val authErrorOutput = """
        authentication_error: Your session has expired.
        Please run `claude login` to authenticate.
    """.trimIndent()

    @Test
    fun `should ask to trust the folder when Claude Code prompts for folder trust`() {
        assertEquals(UsageError.FolderTrustRequired, failure { read(trustPromptOutput) })
    }

    @Test
    fun `should ask to trust the folder when Claude Code shows its newer trust prompt`() {
        assertEquals(UsageError.FolderTrustRequired, failure { read(newTrustPromptOutput) })
    }

    @Test
    fun `should ask to sign in again when Claude Code's session has expired`() {
        assertEquals(UsageError.AuthenticationRequired, failure { read(authErrorOutput) })
    }

    // Reset Time Parsing

    @Test
    fun `should show when the session resets, counted from now`() {
        val sessionQuota = read(sampleClaudeOutput, now = now).sessionQuota

        assertEquals(now + 2 * 3600 + 15 * 60, sessionQuota?.resetsAtSeconds)
        assertEquals("Resets in 2h 15m", sessionQuota?.resetText)
        assertNotNull(sessionQuota?.resetDescription(System.currentTimeMillis() / 1000.0))
    }

    @Test
    fun `should show a session reset 30 minutes away`() {
        assertEquals(now + 30 * 60, read(exhaustedQuotaOutput, now = now).sessionQuota?.resetsAtSeconds)
    }

    @Test
    fun `should print "Resets" before a reset line that lacks it`() {
        val snapshot = read("""
            Current session
            ████████████████░░░░ 65% left
            in 2h
        """.trimIndent(), now = now)

        assertEquals("Resets in 2h", snapshot.sessionQuota?.resetText)
        assertEquals(now + 7200, snapshot.sessionQuota?.resetsAtSeconds)
    }

    @Test
    fun `should show no reset when the screen prints none`() {
        val snapshot = read(usedPercentOutput)

        assertNull(snapshot.sessionQuota?.resetText)
        assertNull(snapshot.sessionQuota?.resetsAtSeconds)
    }

    // Absolute Reset Time Parsing (resetsAt populated)

    @Test
    fun `should know the reset time and elapsed share when the reset is a time of day`() {
        // Pro header with "Resets 4:59pm (America/New_York)"
        val sessionQuota = read(proHeaderOutput).sessionQuota

        // resetsAt must be a moment, not null (enables pace tick)
        assertNotNull(sessionQuota?.resetsAtSeconds, "resetsAt should be populated for 'Resets 4:59pm (TZ)' format")
        assertNotNull(sessionQuota?.percentTimeElapsed(System.currentTimeMillis() / 1000.0), "percentTimeElapsed should be computable")
    }

    @Test
    fun `should know the reset moment when the reset is a date at a time in another time zone`() {
        // real CLI output with "Resets Dec 25 at 4:59am (Asia/Shanghai)"
        val snapshot = read(realCliOutput, now = now)

        // 2:59pm Shanghai is 06:59 UTC — already past at noon UTC, so tomorrow.
        assertEquals(utc(2026, 6, 16, 6, 59), snapshot.sessionQuota?.resetsAtSeconds)
        assertEquals(utc(2026, 12, 24, 20, 59), snapshot.weeklyQuota?.resetsAtSeconds)
    }

    @Test
    fun `should place a reset date already past this year in next year`() {
        // "Resets Jan 15, 3:30pm (America/Los_Angeles)" — past this year, so next year
        val snapshot = read(sampleClaudeOutput, now = now)

        assertEquals(utc(2027, 1, 15, 23, 30), snapshot.weeklyQuota?.resetsAtSeconds)
        assertEquals(utc(2027, 1, 15, 23, 30), snapshot.quota(QuotaType.ModelSpecific("opus"))?.resetsAtSeconds)
    }

    @Test
    fun `should know the reset moments of a Claude API account's windows`() {
        // "Resets 9pm (Asia/Shanghai)" and "Resets Feb 12 at 4pm (Asia/Shanghai)"
        val snapshot = read(claudeApiWithQuotasOutput, now = now)

        // 9pm Shanghai is 13:00 UTC, still ahead at noon UTC
        assertEquals(utc(2026, 6, 15, 13, 0), snapshot.sessionQuota?.resetsAtSeconds)
        assertEquals(utc(2027, 2, 12, 8, 0), snapshot.weeklyQuota?.resetsAtSeconds)
    }

    // Reset on Same Line as Percentage (CLI v2.1.109+ format)

    // Real output from Claude CLI where reset text and percentage share the same line
    // (no separate progress bar line, no separate reset line)
    private val resetOnSameLineOutput = """
        Current session
          Resets 3pm (Europe/Amsterdam)                      27% used


          Current week (all models)
          Resets Apr 16 at 4:59pm (Europe/Amsterdam)         40% used

          Current week (Sonnet only)
          Resets Apr 17 at 11:59am (Europe/Amsterdam)        0% used
    """.trimIndent()

    @Test
    fun `should show each window's percent when the reset and percent share a line`() {
        val snapshot = read(resetOnSameLineOutput)

        assertEquals(73.0, snapshot.sessionQuota?.percentRemaining) // 27% used = 73% remaining
        assertEquals(60.0, snapshot.weeklyQuota?.percentRemaining) // 40% used = 60% remaining
        assertEquals(100.0, snapshot.quota(QuotaType.ModelSpecific("sonnet"))?.percentRemaining) // 0% used
    }

    @Test
    fun `should know each window's reset when the reset and percent share a line`() {
        val snapshot = read(resetOnSameLineOutput, now = now)

        // 3pm Amsterdam (CEST) is 13:00 UTC, still ahead at noon UTC
        assertEquals(utc(2026, 6, 15, 13, 0), snapshot.sessionQuota?.resetsAtSeconds)
        assertEquals(utc(2027, 4, 16, 14, 59), snapshot.weeklyQuota?.resetsAtSeconds)
        // Sonnet shares the all-models weekly reset, as before
        assertEquals(utc(2027, 4, 16, 14, 59), snapshot.quota(QuotaType.ModelSpecific("sonnet"))?.resetsAtSeconds)
    }

    // ANSI Code Handling

    private val ansiColoredOutput = escaped("""
        ⎋[32mCurrent session⎋[0m
        ████████████████░░░░ ⎋[33m65% left⎋[0m
        Resets in 2h 15m
    """.trimIndent())

    @Test
    fun `should show the session when the screen is coloured`() {
        assertEquals(65.0, read(ansiColoredOutput).sessionQuota?.percentRemaining)
    }

    // Account Type Detection from Header

    // /usage header for Max account
    private val maxHeaderOutput = """
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m
    """.trimIndent()

    // /usage header for Pro account
    private val proHeaderOutput = """
        Opus 4.5 · Claude Pro · Organization

        Current session
        █████░░░░░░░░░░░░░░░ 1% used
        Resets 4:59pm (America/New_York)
    """.trimIndent()

    // Real CLI output format with Settings header
    private val realCliOutput = """
        Opus 4.5 · Claude Pro · Some User
        ~/Projects/ClaudeBar

        Settings: Status  Config  Usage (tab to cycle)

        Current session
        ▌                                                  1% used
        Resets 2:59pm (Asia/Shanghai)

        Current week (all models)
        █████                                              16% used
        Resets Dec 25 at 4:59am (Asia/Shanghai)

        Extra usage
        Extra usage not enabled • /extra-usage to enable

        Esc to cancel
    """.trimIndent()

    // Real CLI output with ANSI escape codes (from actual terminal)
    private val realCliOutputWithAnsi = escaped("""
        ⎋[?25l⎋[?2004h⎋[?25h⎋[?2004l⎋[?2026h
        Opus 4.5 · Claude Pro · Some User
        ~/Projects/ClaudeBar

        ⎋[33mSettings:⎋[0m Status  Config  ⎋[7mUsage⎋[0m (tab to cycle)

        ⎋[1mCurrent session⎋[0m
        ⎋[34m▌⎋[0m                                                  1% used
        Resets 2:59pm (Asia/Shanghai)

        ⎋[1mCurrent week (all models)⎋[0m
        ⎋[34m█████⎋[0m                                              16% used
        Resets Dec 25 at 4:59am (Asia/Shanghai)

        ⎋[1mExtra usage⎋[0m
        Extra usage not enabled • /extra-usage to enable

        Esc to cancel
        ⎋[?2026l
    """.trimIndent())

    @Test
    fun `should show the Pro plan, session and weekly windows, and no extra usage, under the Settings header`() {
        val snapshot = read(realCliOutput)

        assertEquals(AccountTier.ClaudePro, snapshot.accountTier)
        assertEquals(99.0, snapshot.sessionQuota?.percentRemaining) // 1% used = 99% left
        assertEquals(84.0, snapshot.weeklyQuota?.percentRemaining) // 16% used = 84% left
        assertNull(snapshot.costUsage) // Extra usage not enabled
    }

    @Test
    fun `should show the Pro plan and windows when the real screen carries terminal escape codes`() {
        val snapshot = read(realCliOutputWithAnsi)

        assertEquals(AccountTier.ClaudePro, snapshot.accountTier)
        assertEquals(99.0, snapshot.sessionQuota?.percentRemaining) // 1% used = 99% left
        assertEquals(84.0, snapshot.weeklyQuota?.percentRemaining) // 16% used = 84% left
    }

    @Test
    fun `should show the Max plan when the header names it`() {
        assertEquals(AccountTier.ClaudeMax, read(maxHeaderOutput).accountTier)
    }

    @Test
    fun `should show the Pro plan when the header names it`() {
        assertEquals(AccountTier.ClaudePro, read(proHeaderOutput).accountTier)
    }

    @Test
    fun `should show the Max plan when there is no header but there are quotas`() {
        assertEquals(AccountTier.ClaudeMax, read("Current session\n75% left").accountTier)
    }

    @Test
    fun `should show the Max plan when there is no header but quotas and extra usage`() {
        val output = """
            Current session
            75% left

            Extra usage
            $5.00 / $20.00 spent
        """.trimIndent()

        // Both Max and Pro can have Extra usage, defaults to Max without header
        assertEquals(AccountTier.ClaudeMax, read(output).accountTier)
    }

    // Extra Usage Parsing

    private val proWithExtraUsageOutput = """
        Opus 4.5 · Claude Pro · Organization

        Current session
        █████░░░░░░░░░░░░░░░ 1% used
        Resets 4:59pm (America/New_York)

        Current week (all models)
        █████████████████░░░ 36% used
        Resets Dec 25 at 2:59pm (America/New_York)

        Extra usage
        █████░░░░░░░░░░░░░░░ 27% used
        $5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)
    """.trimIndent()

    private val maxWithExtraUsageNotEnabled = """
        Opus 4.5 · Claude Max · Organization

        Current session
        ████████████████░░░░ 82% used
        Resets 3pm (Asia/Shanghai)

        Extra usage
        Extra usage not enabled · /extra-usage to enable
    """.trimIndent()

    @Test
    fun `should show a Pro account's extra-usage spend against its limit`() {
        val costUsage = read(proWithExtraUsageOutput).costUsage

        assertEquals(dollars("5.41"), costUsage?.totalCostNanos)
        assertEquals(dollars("20.00"), costUsage?.budgetNanos)
        assertEquals(CostUsage.Kind.EXTRA_USAGE, costUsage?.kind)
    }

    @Test
    fun `should show extra-usage spend, limit and reset`() {
        val costUsage = read("""
            Current session
            75% left

            Extra usage
            $5.41 / $20.00 spent · Resets Jan 1, 2026
        """.trimIndent()).costUsage

        assertEquals(dollars("5.41"), costUsage?.totalCostNanos)
        assertEquals(dollars("20.00"), costUsage?.budgetNanos)
        assertTrue(costUsage?.resetText?.contains("Resets Jan 1, 2026") == true)
    }

    @Test
    fun `should show extra-usage spend when the amounts have no dollar sign`() {
        val costUsage = read("""
            Current session
            75% left

            Extra usage
            5.41 / 20.00 spent
        """.trimIndent()).costUsage

        assertEquals(dollars("5.41"), costUsage?.totalCostNanos)
        assertEquals(dollars("20.00"), costUsage?.budgetNanos)
    }

    @Test
    fun `should show extra-usage spend when the amounts have thousands separators`() {
        val costUsage = read("""
            Current session
            75% left

            Extra usage
            $1,234.50 / $2,000.00 spent
        """.trimIndent()).costUsage

        assertEquals(dollars("1234.50"), costUsage?.totalCostNanos)
        assertEquals(dollars("2000.00"), costUsage?.budgetNanos)
    }

    @Test
    fun `should show no extra usage when it isn't enabled`() {
        val snapshot = read(maxWithExtraUsageNotEnabled)

        assertNull(snapshot.costUsage)
        assertEquals(18.0, snapshot.sessionQuota?.percentRemaining)
    }

    @Test
    fun `should show no extra usage when the screen has no extra-usage section`() {
        assertNull(read("Current session\n65% left").costUsage)
    }

    @Test
    fun `should show a Pro account's quotas together with its extra-usage spend`() {
        val snapshot = read(proWithExtraUsageOutput)

        assertEquals(AccountTier.ClaudePro, snapshot.accountTier)
        assertEquals(dollars("5.41"), snapshot.costUsage?.totalCostNanos)
        assertEquals(dollars("20.00"), snapshot.costUsage?.budgetNanos)
        assertTrue(snapshot.quotas.isNotEmpty())
    }

    @Test
    fun `should know when extra usage resets when the reset sits mid-line`() {
        // "$5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)" — "Resets" appears mid-line, not at the start
        val snapshot = read(proWithExtraUsageOutput, now = now)

        assertEquals(utc(2026, 1, 1, 5, 0), snapshot.costUsage?.resetsAtSeconds,
            "resetsAt should be populated when 'Resets' appears mid-line in cost line")
        assertTrue(snapshot.costUsage?.resetText?.contains("Resets Jan 1, 2026") == true)
    }

    // API Usage Billing Account Detection

    // Real output from API Usage Billing account showing subscription-only message
    private val apiUsageBillingOutput = """
        Sonnet 4.5 · API Usage Billing · dzienisz
        ~/Library/Application Support/ClaudeBar/Probe

        Settings: Status  Config  Usage (tab to cycle)

        /usage is only available for subscription plans.

        Esc to cancel
    """.trimIndent()

    // Subscription account that has added Extra Usage credits. The CLI header shows only
    // "API Usage Billing" (no Pro/Max tier word), but valid quota bars still appear — there is
    // NO "/usage is only available for subscription plans" error.
    private val apiUsageBillingWithQuotasOutput = """
        ▐▛███▜▌   Claude Code v2.1.34
        ▝▜█████▛▘  Sonnet 4.5 · API Usage Billing · user@example.com
        ▘▘ ▝▝    ~/Library/Application Support/ClaudeBar/Probe

        ❯ /usage
        Settings:  Status   Config   Usage  (←/→ or tab to cycle)


        Current session
        ██▌                                                5% used
        Resets 9pm (Asia/Shanghai)

        Current week (all models)
        █████████▌                                         19% used
        Resets Feb 12 at 4pm (Asia/Shanghai)

        Esc to cancel
    """.trimIndent()

    // Claude API account (subscription with quotas, different from API Usage Billing)
    private val claudeApiWithQuotasOutput = """
        ▐▛███▜▌   Claude Code v2.1.34
        ▝▜█████▛▘  Sonnet 4.5 · Claude API
        ▘▘ ▝▝    ~/Library/Application Support/ClaudeBar/Probe

        ❯ /usage
        Settings:  Status   Config   Usage  (←/→ or tab to cycle)


        Current session
        ██▌                                                5% used
        Resets 9pm (Asia/Shanghai)

        Current week (all models)
        █████████▌                                         19% used
        Resets Feb 12 at 4pm (Asia/Shanghai)

        Current week (Sonnet only)
        ███▌                                               7% used
        Resets Feb 9 at 8pm (Asia/Shanghai)

        Esc to cancel
    """.trimIndent()

    @Test
    fun `should show a subscription plan when the header says API Usage Billing but quotas show`() {
        // header has "API Usage Billing" but no subscription-only error, and the output contains
        // real quota bars (subscription with Extra Usage credits).
        val accountType = read(apiUsageBillingWithQuotasOutput).accountTier

        // must NOT be claudeApi; quota fallback defaults to claudeMax
        assertNotEquals(AccountTier.ClaudeApi, accountType)
        assertEquals(AccountTier.ClaudeMax, accountType)
    }

    @Test
    fun `should show a subscriber's windows when Extra Usage credits put API Usage Billing in the header`() {
        val snapshot = read(apiUsageBillingWithQuotasOutput)

        // quotas parsed; no fall-through to /cost
        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier)
        assertEquals(95.0, snapshot.sessionQuota?.percentRemaining) // 5% used → 95% remaining
        assertEquals(81.0, snapshot.weeklyQuota?.percentRemaining) // 19% used → 81% remaining
    }

    @Test
    fun `should fall back to session cost when Claude says usage is for subscription plans only`() {
        assertEquals(UsageError.SubscriptionRequired, failure { read("/usage is only available for subscription plans.") })
    }

    @Test
    fun `should show the Max plan when a Claude API header comes with quotas`() {
        val output = """
            Sonnet 4.5 · Claude API

            Current session
            75% left
        """.trimIndent()

        // Should NOT be treated as claudeApi (which is for pay-as-you-go); defaults to claudeMax since it has quota data
        assertEquals(AccountTier.ClaudeMax, read(output).accountTier)
    }

    @Test
    fun `should show a Claude API account's session, weekly and Sonnet windows`() {
        val snapshot = read(claudeApiWithQuotasOutput)

        // Should parse quotas, not throw subscriptionRequired
        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier) // Defaults to Max for API accounts with quotas
        assertEquals(95.0, snapshot.sessionQuota?.percentRemaining) // 5% used = 95% remaining
        assertEquals(81.0, snapshot.weeklyQuota?.percentRemaining) // 19% used = 81% remaining
        assertEquals(93.0, snapshot.quota(QuotaType.ModelSpecific("sonnet"))?.percentRemaining) // 7% used = 93% remaining
    }

    @Test
    fun `should fall back to session cost when an API-billing account opens the usage screen`() {
        assertEquals(UsageError.SubscriptionRequired, failure { read(apiUsageBillingOutput) })
    }

    // Terminal Rendering

    @Test
    fun `should read the session where cursor movements placed the text`() {
        // "Hello" + move 5 columns right + "World", on the label and the reset rows
        val snapshot = read("Current session\r\n████████\u001B[30C20% used\r\nResets\u001B[1Cin 2h 15m", now = now)

        assertEquals(80.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals("Resets in 2h 15m", snapshot.sessionQuota?.resetText)
        assertEquals(now + 2 * 3600 + 15 * 60, snapshot.sessionQuota?.resetsAtSeconds)
    }

    @Test
    fun `should show the session when colour codes sit inside its label`() {
        // Green colored text + reset + normal
        assertEquals(42.0, read("\u001B[32mCurrent\u001B[0m session\n\u001B[33m42%\u001B[0m left").sessionQuota?.percentRemaining)
    }

    @Test
    fun `should show the windows that scrolled off the visible screen`() {
        // the CLI /usage screen grew past 50 rows (usage-contribution report), pushing the quota
        // sections above the visible screen into scrollback
        val filler = (1..60).joinToString("\n") { "contributing insight line $it" }
        val output = """
            |Current session
            |██████████████████████████████▌                    61% used
            |Resets 1:09am (America/Chicago)
            |
            |Current week (all models)
            |█████████                                          18% used
            |Resets Jul 2 at 4:59am (America/Chicago)
            |
            |Current week (Fable)
            |████████████████                                   32% used
            |Resets Jul 2 at 5:59am (America/Chicago)
            |
            |What's contributing to your limits usage?
            |$filler
        """.trimMargin()

        val snapshot = read(output)

        assertEquals(39.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(82.0, snapshot.weeklyQuota?.percentRemaining)
        assertEquals(68.0, snapshot.quota(QuotaType.ModelSpecific("fable"))?.percentRemaining)
    }

    @Test
    fun `should show the session and weekly windows from a cleanly rendered screen`() {
        // clean terminal output as rendered by SwiftTerm
        val output = """
            Opus 4.5 · Claude Max · user@example.com's Organization

            Current session
            ████████                                         20% used
            Resets 6pm (Asia/Shanghai)

            Current week (all models)
            ███████████▌                                     23% used
            Resets Jan 15, 4pm (Asia/Shanghai)
        """.trimIndent()

        val snapshot = read(output)

        assertEquals(80.0, snapshot.sessionQuota?.percentRemaining) // 20% used = 80% remaining
        assertEquals(77.0, snapshot.weeklyQuota?.percentRemaining) // 23% used = 77% remaining
    }

    // Terminal Rendering Deduplication

    @Test
    fun `should show each reset once, with its moment, when a redraw doubles the reset line`() {
        // terminal rendering artifact where cursor misalignment causes reset text to appear twice on a single line
        val output = """
            Opus 4.5 · Claude Pro · Organization

            Current session
            █████░░░░░░░░░░░░░░░ 6% used
            Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)

            Current week (all models)
            █████████████████░░░ 36% used
            Resets Dec 25 at 2:59pm (America/New_York)Resets Dec 25 at 2:59pm (America/New_York)
        """.trimIndent()

        val snapshot = read(output, now = now)

        // quotas parse with clean reset text
        val session = snapshot.sessionQuota
        assertEquals(utc(2026, 6, 15, 20, 59), session?.resetsAtSeconds, "resetsAt should be populated despite duplicated text")
        assertEquals("Resets 4:59pm (America/New_York)", session?.resetText)
        // Should NOT contain the duplication
        assertEquals(2, session?.resetText?.split("Resets")?.size, "resetText should contain 'Resets' exactly once (prefix + content)")

        val weekly = snapshot.weeklyQuota
        assertEquals(utc(2026, 12, 25, 19, 59), weekly?.resetsAtSeconds, "weekly resetsAt should be populated despite duplicated text")
        assertEquals("Resets Dec 25 at 2:59pm (America/New_York)", weekly?.resetText)
    }

    @Test
    fun `should print "Resets" once when a redraw doubles the reset line`() {
        val text = """
            Current session
            ████ 6% used
            Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)
        """.trimIndent()

        val resetText = read(text).sessionQuota?.resetText!!

        val resetsCount = resetText.split("Resets").size - 1
        assertEquals(1, resetsCount, "Should contain 'Resets' exactly once, got $resetsCount in: $resetText")
    }

    // Unfinished / API-billing Screens (issue #271)

    /** The Usage tab as it looks before the quota request comes back. */
    private val stillLoadingOutput = """
        Claude Code v2.1.251
        Opus 5 (1M context) · Claude Max

          Settings  Status  Config  Usage  Stats

          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write

            Loading usage data…

          Esc to cancel
    """.trimIndent()

    /** The Usage tab for a session the CLI resolved to API billing: a cost panel, no quota bars, and nothing left to wait for. */
    private val apiBillingCostPanelOutput = """
        Claude Code v2.1.251
        Opus 5 (1M context) · API Usage Billing

          Settings  Status  Config  Usage  Stats

          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Total duration (wall): 0s
            Total code changes:    0 lines added, 0 lines removed
            Usage:                 0 input, 0 output, 0 cache read, 0 cache write

          Esc to cancel
    """.trimIndent()

    private val subscriptionMisread =
        "The Claude CLI did not see this account's subscription — its usage screen reported API billing instead of a plan. " +
            "Run `claude auth login` again, or switch Claude to API mode in Settings."

    @Test
    fun `should say usage never finished loading when the screen is still loading`() {
        assertEquals(
            UsageError.ExecutionFailed("Claude usage data did not finish loading — the usage endpoint may be rate limited. Try again in a moment."),
            failure { read(stillLoadingOutput) },
        )
    }

    @Test
    fun `should show session cost when the usage panel has lost its header`() {
        val panel = "Session\nTotal cost: \$0.0000\nTotal duration (API): 0s\nEsc to cancel"
        assertEquals(UsageError.SubscriptionRequired, failure { read(panel) })
    }

    @Test
    fun `should explain reconnection when a subscription account shows a headerless cost panel`() = claude { claude ->
        claude.writeClaudeConfig(email = "user@example.com", billingType = "stripe_subscription")
        assertEquals(UsageError.ExecutionFailed(subscriptionMisread), failure {
            claude.readUsageScreen("Session\nTotal cost: \$0.0000\nTotal duration (API): 0s\nEsc to cancel")
        })
    }

    @Test
    fun `should fall back to session cost when the screen shows the API-billing cost panel`() {
        assertEquals(UsageError.SubscriptionRequired, failure { read(apiBillingCostPanelOutput) })
    }

    @Test
    fun `should say the CLI missed the subscription when a subscriber gets the API-billing cost panel (#271)`() = claude { claude ->
        // A Max plan billed through Apple still renders the API-billing cost panel when the CLI
        // cannot see the subscription (#271). Answering with `/cost` would report $0.00 and no
        // quota, and would stop the provider from trying the usage API. Fail instead.
        claude.writeClaudeConfig(email = "user@example.com", billingType = "apple_subscription")

        assertEquals(UsageError.ExecutionFailed(subscriptionMisread), failure { claude.readRawUsageScreen(apiBillingCostPanelOutput) })
    }

    @Test
    fun `should fall back to session cost when a pay-as-you-go account gets the cost panel`() = claude { claude ->
        claude.writeClaudeConfig(email = "user@example.com", billingType = "api")

        assertEquals(UsageError.SubscriptionRequired, failure { claude.readRawUsageScreen(apiBillingCostPanelOutput) })
    }

    // /cost Hand-offs That Would Misreport (issue #317)

    /**
     * The other route into `/cost`. "/usage is only available for subscription plans" hands off to
     * `cliCost`; a subscription that reaches it gets the probe session's own $0.00 — and because
     * that *succeeds*, the usage API that can read its real quota never runs.
     */
    private val subscriptionOnlyMessageOutput = """
        Claude Code v2.1.274
        Opus 5 (1M context) · API Usage Billing

          Session
            Total cost:            $0.0000
            Total duration (API):  0s
            Total duration (wall): 1s
            Total code changes:    0 lines added, 0 lines removed
            Usage: 0 input, 0 output, 0 cache read, 0 cache write

        /usage is only available for subscription plans. /cost shows session cost.
    """.trimIndent()

    @Test
    fun `should say the CLI missed the subscription when a subscriber is told usage is for subscription plans only (#317)`() = claude { claude ->
        claude.writeClaudeConfig(email = "user@example.com", billingType = "apple_subscription")

        assertEquals(UsageError.ExecutionFailed(subscriptionMisread), failure { claude.readRawUsageScreen(subscriptionOnlyMessageOutput) })
    }

    @Test
    fun `should fall back to session cost when a pay-as-you-go account is told usage is for subscription plans only`() = claude { claude ->
        claude.writeClaudeConfig(email = "user@example.com", billingType = "api")

        assertEquals(UsageError.SubscriptionRequired, failure { claude.readRawUsageScreen(subscriptionOnlyMessageOutput) })
    }

    @Test
    fun `should show the windows when a subscriber's header mentions API Usage Billing beside quotas`() {
        // Extra Usage credits put "API Usage Billing" in a subscription header — the quota bars
        // are what decide, not the header.
        val output = """
            Claude Code v2.1.251
            Opus 5 (1M context) · API Usage Billing

            Current session
            ████ 25% used

            Current week (all models)
            ████ 60% used
        """.trimIndent()

        val snapshot = read(output)

        assertEquals(75.0, snapshot.sessionQuota?.percentRemaining)
        assertEquals(40.0, snapshot.weeklyQuota?.percentRemaining)
    }

    // Helpers

    /** The screen as the `cli` data source reads it: rendered, then scripted, with [config] as `~/.claude.json` when given. */
    private fun read(screen: String, config: String? = null, now: Double? = null): UsageSnapshot {
        val claude = ClaudeHarness()
        try {
            if (now != null) claude.now = now
            if (config != null) File(claude.home, ".claude.json").writeText(config)
            return claude.readRawUsageScreen(screen)
        } finally {
            claude.cleanUp()
        }
    }

    private fun claude(test: (ClaudeHarness) -> Unit) {
        val claude = ClaudeHarness()
        try {
            test(claude)
        } finally {
            claude.cleanUp()
        }
    }

    /** The `UsageError` [read] threw. */
    private fun failure(read: () -> UsageSnapshot): UsageError = assertThrows(UsageError::class.java) { read() }

    private fun utc(year: Int, month: Int, day: Int, hour: Int, minute: Int): Double =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, ZoneOffset.UTC).toEpochSecond().toDouble()
}
