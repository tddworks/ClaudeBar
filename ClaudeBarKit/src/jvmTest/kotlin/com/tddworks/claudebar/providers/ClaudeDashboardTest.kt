package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.quotas.AccountTier
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** #328: the Dashboard opens claude.ai usage settings for a subscription, and Console billing for an API account — `claude.json`'s `dashboardByPlan`. */
class ClaudeDashboardTest {
    private val subscriptionUsageURL = "https://claude.ai/new#settings/usage"
    private val consoleBillingURL = "https://console.anthropic.com/settings/billing"

    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    /** [screen] is what `/usage` shows; `/cost`, when `/usage` hands off to it, shows [cost]. */
    private fun claude(afterReading: String, cost: String = ""): Provider {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { run -> CLIResult(if ("/cost" in run) cost else afterReading) }
        val provider = claude.provider()
        provider.refreshPlain()
        return provider
    }

    @Test
    fun `should open claude-ai usage settings from the dashboard for a Max account (#328)`() {
        val provider = claude(afterReading = "Opus 4.7 · Claude Max\nCurrent session\n████ 65% left")
        assertEquals(AccountTier.ClaudeMax, provider.defaultAccount.snapshot?.accountTier)
        assertEquals(subscriptionUsageURL, provider.plainDashboardURL)
    }

    @Test
    fun `should open claude-ai usage settings from the dashboard for a Pro account (#328)`() {
        val provider = claude(afterReading = "Sonnet 4.6 · Claude Pro\nCurrent session\n████ 65% left")
        assertEquals(AccountTier.ClaudePro, provider.defaultAccount.snapshot?.accountTier)
        assertEquals(subscriptionUsageURL, provider.plainDashboardURL)
    }

    @Test
    fun `should open Console billing from the dashboard for an API account (#328)`() {
        val provider = claude(
            afterReading = "/usage is only available for subscription plans.",
            cost = "Total cost:            \$1.23\nTotal duration (API):  1m 30s",
        )
        assertEquals(AccountTier.ClaudeApi, provider.defaultAccount.snapshot?.accountTier)
        assertEquals(consoleBillingURL, provider.plainDashboardURL)
    }

    @Test
    fun `should open claude-ai usage settings from the dashboard for other plans and before the first refresh`() {
        val definition = TestDefinitions.builtIn("claude")

        assertEquals(subscriptionUsageURL, claude.provider().plainDashboardURL)
        assertEquals(subscriptionUsageURL, definition.profile.links.dashboard(AccountTier.Custom("Enterprise")))
        assertEquals(subscriptionUsageURL, definition.profile.links.dashboard(null))
    }
}
