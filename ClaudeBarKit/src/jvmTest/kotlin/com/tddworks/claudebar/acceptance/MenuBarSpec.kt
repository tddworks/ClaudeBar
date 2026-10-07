package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.monitoring.StubUsage
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.quotas.QuotaStatus
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Feature: Menu Bar
 *
 * The menu bar icon reflects the overall quota status across
 * all enabled providers.
 *
 * Behaviors covered:
 * - #2: Menu bar icon reflects worst quota status across providers
 */
class MenuBarSpec {
    private val products = StubbedProducts()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    // Scenario: Overall status calculation

    @Test
    fun `should stay healthy in the menu bar when only a turned-off provider is critical`() = runTest {
        val codex = products.product("codex", StubUsage.of(session(5.0)))
        codex.defaultAccount.isEnabled = false
        val monitor = products.monitor(products.product("claude", StubUsage.of(session(70.0))), codex)

        monitor.refreshAll()

        assertEquals(QuotaStatus.HEALTHY, monitor.overallStatus)
    }

    @Test
    fun `should show a warning for the selected provider when it has 30% left`() = runTest {
        val monitor = products.monitor(products.product("claude", StubUsage.of(session(30.0))))

        monitor.refresh("claude")

        assertEquals(QuotaStatus.WARNING, monitor.selectedProviderStatus)
    }

    @Test
    fun `should show healthy before any quota has been read`() {
        val monitor = products.monitor(products.product("claude"))

        assertEquals(QuotaStatus.HEALTHY, monitor.overallStatus)
        assertEquals(QuotaStatus.HEALTHY, monitor.selectedProviderStatus)
    }
}
