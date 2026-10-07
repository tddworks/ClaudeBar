package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.monitoring.StubUsage
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.ClaudeHarness
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Feature: Quota Display
 *
 * Users see quota cards with percentages, progress bars, status badges,
 * and reset times after a provider refresh.
 *
 * Behaviors covered:
 * - #8: User sees account info card (email, tier badge, freshness)
 * - #9: User sees quota cards with percentage, progress bar, reset time
 * - #10: User toggles "Remaining" vs "Used" display mode
 * - #13: Unavailable provider shows error message with guidance
 * - #14: Over-quota displays negative percentages
 */
class QuotaDisplaySpec {
    private val products = StubbedProducts()
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() {
        products.cleanUp()
        claude.cleanUp()
    }

    private fun cliAnswers(screen: String) {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { CLIResult(screen) }
    }

    private fun quota(percentRemaining: Double, providerId: String = "claude") =
        UsageQuota(percentRemaining, QuotaType.Session, providerId, null, null, null, null, null, null, null, null, null, null)

    // Scenario: Account info displays after refresh (#8)

    @Test
    fun `should show the account's email and Claude Max plan once quotas are read`() = runTest {
        cliAnswers(
            """
            Claude Code v1.0.27
            Current session
            ████████████████░░░░ 65% left
            Resets in 2h 15m
            Account: user@example.com
            Organization: Acme Corp
            Login method: Claude Max
            """.trimIndent(),
        )
        claude.writeClaudeConfig(email = "user@example.com", displayName = "Acme Corp")
        val provider = claude.provider()
        val monitor = products.monitor(provider)

        monitor.refresh("claude")

        val snapshot = provider.defaultAccount.snapshot
        assertNotNull(snapshot)
        assertEquals("user@example.com", snapshot?.accountEmail)
        assertEquals(AccountTier.ClaudeMax, snapshot?.accountTier)
    }

    // Scenario: Quota cards display correctly after refresh (#9)

    @Test
    fun `should show a healthy session at 65% and a warning weekly at 35%`() = runTest {
        cliAnswers(
            """
            Current session
            ████████████████░░░░ 65% left
            Resets in 2h 15m
            Current week (all models)
            ██████████░░░░░░░░░░ 35% left
            Resets Jan 15, 3:30pm
            Account: user@example.com
            Login method: Claude Max
            """.trimIndent(),
        )
        val provider = claude.provider()
        val monitor = products.monitor(provider)

        monitor.refresh("claude")

        val snapshot = provider.defaultAccount.snapshot
        assertEquals(2, snapshot?.quotas?.size)
        val session = snapshot?.quota(QuotaType.Session)
        assertEquals(65.0, session?.percentRemaining)
        assertEquals(QuotaStatus.HEALTHY, session?.status)
        val weekly = snapshot?.quota(QuotaType.Weekly)
        assertEquals(35.0, weekly?.percentRemaining)
        assertEquals(QuotaStatus.WARNING, weekly?.status)
    }

    @Test
    fun `should show the session depleted when 0% is left`() = runTest {
        cliAnswers(
            """
            Current session
            ░░░░░░░░░░░░░░░░░░░░ 0% left
            Resets in 30m
            """.trimIndent(),
        )
        val provider = claude.provider()
        val monitor = products.monitor(provider)

        monitor.refresh("claude")

        val session = provider.defaultAccount.snapshot?.quota(QuotaType.Session)
        assertEquals(0.0, session?.percentRemaining)
        assertEquals(QuotaStatus.DEPLETED, session?.status)
    }

    // Scenario: Toggle between Remaining and Used display (#10)

    @Test
    fun `should show 35% used when 65% is left and the person views usage as used`() {
        val quota = quota(65.0)

        assertEquals(65.0, quota.percentRemaining)
        assertEquals(35.0, quota.percentUsed)
    }

    @Test
    fun `should show 100% used when nothing is left`() {
        assertEquals(100.0, quota(0.0).percentUsed)
    }

    // Scenario: Unavailable provider shows error message (#13)

    @Test
    fun `should show no quotas and tell the person the session expired when the login is refused`() = runTest {
        val provider = products.product("claude", StubUsage { throw UsageError.SessionExpired() })
        val monitor = products.monitor(provider)

        monitor.refresh("claude")

        assertNull(provider.defaultAccount.snapshot)
        assertNotNull(provider.defaultAccount.lastError)
        assertTrue(provider.defaultAccount.lastError?.message.orEmpty().contains("Session expired"))
    }

    // Scenario: Over-quota displays negative percentages (#14)

    @Test
    fun `should show depleted and keep -98% when Copilot is over its quota`() {
        val quota = quota(-98.0, providerId = "copilot")

        assertEquals(QuotaStatus.DEPLETED, quota.status)
        assertEquals(-98.0, quota.percentRemaining)
    }
}
