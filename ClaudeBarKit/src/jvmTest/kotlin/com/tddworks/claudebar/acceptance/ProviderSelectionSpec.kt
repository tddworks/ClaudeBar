package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.monitoring.StubUsage
import com.tddworks.claudebar.monitoring.StubbedProducts
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Feature: Provider Selection
 *
 * Users switch between AI providers via pills in the menu bar.
 * The monitor coordinates selection, refresh, and state transitions.
 *
 * Behaviors covered:
 * - #4: User clicks a provider pill → switches view and triggers refresh
 * - #5: Only enabled providers appear as pills
 */
class ProviderSelectionSpec {
    private val products = StubbedProducts()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    // Scenario: Switch to a different provider

    @Test
    fun `should select Codex and show its 40% left when the person picks the Codex pill and it refreshes`() = runTest {
        val codex = products.product("codex", StubUsage.of(session(40.0)))
        val monitor = products.monitor(products.product("claude", StubUsage.of(session(70.0))), codex)
        assertEquals("claude", monitor.selectedProviderId)

        monitor.selectProvider("codex")
        monitor.refresh("codex")

        assertEquals("codex", monitor.selectedProviderId)
        assertEquals(40.0, codex.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
    }

    // Scenario: Only enabled providers appear as pills

    @Test
    fun `should show a pill for every provider that is on`() {
        val monitor = products.monitor(products.product("claude"), products.product("codex"))

        assertEquals(listOf("claude", "codex"), monitor.lineup.map { it.id })
    }
}
