package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.providers.ClaudeHarness
import com.tddworks.claudebar.providers.ClaudeNoGuestPasses
import com.tddworks.claudebar.providers.GuestPasses
import com.tddworks.claudebar.providers.StubbedProvider
import com.tddworks.claudebar.providers.plainDashboardURL
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * Feature: Action Bar
 *
 * Users interact with action buttons: Dashboard, Refresh, Share, Settings, Quit.
 *
 * Behaviors covered:
 * - #24: User clicks Dashboard → opens provider's web dashboard in browser
 * - #25: User clicks Share (Claude only) → shows referral link overlay
 */
class ActionBarSpec {
    private val stub = StubbedProvider()
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() {
        stub.cleanUp()
        claude.cleanUp()
    }

    // Scenario: Dashboard opens correct URL per provider (#24)

    @Test
    fun `should open GitHub's Copilot features page from Copilot's Dashboard (#24)`() {
        assertEquals("https://github.com/settings/copilot/features", stub.makeProvider("copilot").plainDashboardURL)
    }

    @Test
    fun `should offer no Dashboard for Antigravity (#24)`() {
        assertNull(stub.makeProvider("antigravity").plainDashboardURL)
    }

    @Test
    fun `should open the AWS Bedrock console from Bedrock's Dashboard (#24)`() {
        assertEquals("https://console.aws.amazon.com/bedrock/home", stub.makeProvider("bedrock").plainDashboardURL)
    }

    @Test
    fun `should open Zai's subscription page from Zai's Dashboard (#24)`() {
        assertEquals("https://z.ai/subscribe", stub.makeProvider("zai").plainDashboardURL)
    }

    // Scenario: Share Claude Code guest passes (#25)

    @Test
    fun `should offer Claude guest passes only when ClaudeBar can read them (#25)`() {
        val withoutPasses = claude.provider().defaultAccount
        val withPasses = claude.provider(guestPasses = GuestPasses(ClaudeNoGuestPasses)).defaultAccount

        assertNull(withoutPasses.guestPasses)
        assertNotNull(withPasses.guestPasses)
    }
}
