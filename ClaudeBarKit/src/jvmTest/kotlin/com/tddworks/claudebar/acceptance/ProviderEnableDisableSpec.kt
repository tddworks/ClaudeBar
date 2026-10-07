package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.monitoring.StubbedProducts
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Feature: Provider Enable/Disable
 *
 * Users toggle providers on/off from Settings. Disabled providers
 * are hidden from pills and excluded from monitoring.
 *
 * Behaviors covered:
 * - #47: User toggles provider on → appears in pills, included in monitoring
 * - #48: Enabled state persists across restarts
 */
class ProviderEnableDisableSpec {
    private val products = StubbedProducts()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    // Scenario: Enable a provider

    @Test
    fun `should add Codex to the lineup and keep Claude selected when the person turns Codex on`() {
        val codex = products.product("codex")
        codex.defaultAccount.isEnabled = false
        val monitor = products.monitor(products.product("claude"), codex)
        assertEquals("claude", monitor.selectedProviderId)

        monitor.setProviderEnabled("codex", enabled = true)

        assertTrue(codex.defaultAccount.isEnabled)
        assertEquals(listOf("claude", "codex"), monitor.lineup.map { it.id })
        assertEquals("claude", monitor.selectedProviderId)
    }

    // Scenario: Enabled state persists across restarts

    @Test
    fun `should remember whether the person turned a provider on or off`() {
        val settings = IsolatedSettings()

        settings.repository.setEnabled(false, "codex")
        assertEquals(false, settings.reopened().isEnabled("codex", defaultValue = true))

        settings.repository.setEnabled(true, "codex")
        assertEquals(true, settings.reopened().isEnabled("codex", defaultValue = true))
    }
}
