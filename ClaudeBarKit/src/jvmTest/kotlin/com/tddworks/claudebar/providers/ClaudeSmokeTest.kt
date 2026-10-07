package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class ClaudeSmokeTest {
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    @Test
    fun `should show the session, weekly and Opus windows with their resets when Claude prints a plain usage screen`() {
        val usage = claude.readUsageScreen("""
            Claude Code v1.0.27

            Current session
            ████████████████░░░░ 65% left
            Resets in 2h 15m

            Current week (all models)
            ██████████░░░░░░░░░░ 35% left
            Resets Jan 15, 3:30pm (America/Los_Angeles)

            Current week (Opus)
            ████████████████████ 80% left
        """.trimIndent())

        assertEquals(65.0, usage.sessionQuota?.percentRemaining)
        assertEquals("Resets in 2h 15m", usage.sessionQuota?.resetText)
        assertNotNull(usage.sessionQuota?.resetsAtSeconds)
        assertEquals(35.0, usage.weeklyQuota?.percentRemaining)
        assertEquals(80.0, usage.quota(QuotaType.ModelSpecific("opus"))?.percentRemaining)
        assertEquals(AccountTier.ClaudeMax, usage.accountTier)
    }

    @Test
    fun `should show an over-limit session, the Max plan and extra-usage spend when Claude's usage API answers`() {
        val usage = claude.readAPIResponse(
            """{"five_hour":{"utilization":105,"resets_at":"2099-01-01T00:00:00Z"},"extra_usage":{"is_enabled":true,"used_credits":1234,"monthly_limit":5000}}""",
            subscriptionType = "claude_max",
        )

        assertEquals(-5.0, usage.sessionQuota?.percentRemaining)
        assertEquals(AccountTier.ClaudeMax, usage.accountTier)
        assertEquals(12_340_000_000L, usage.costUsage?.totalCostNanos)
        assertEquals(50_000_000_000L, usage.costUsage?.budgetNanos)
    }
}
