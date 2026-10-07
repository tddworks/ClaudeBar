package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.monitoring.StubUsage
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.ClaudeHarness
import com.tddworks.claudebar.providers.InMemoryProviderSettings
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Feature: Refresh
 *
 * Users refresh quota data manually or via background sync.
 *
 * Behaviors covered:
 * - #15: User clicks Refresh → fetches latest quota for current provider
 * - #18: Background sync auto-refreshes at configured interval
 * - #204: Power-conscious background refresh — the API's floor governs only the background loop
 */
class RefreshSpec {
    private val products = StubbedProducts()
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() {
        products.cleanUp()
        claude.cleanUp()
    }

    private val usageScreen = """
        Current session
        ████████████████░░░░ 42% left
        Resets in 2h 15m
    """.trimIndent()

    // Scenario: Background sync

    @Test
    fun `should keep showing the CLI's quotas when Claude refreshes in the background in CLI mode`() = runTest {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { CLIResult(usageScreen) }
        val provider = claude.provider()
        val monitor = products.monitor(provider, clock = SuspendingClock, scope = backgroundScope)

        monitor.startMonitoring(600.0).take(1).toList()
        monitor.stopMonitoring()

        // It refreshed through the CLI: no silent CLI → API swap.
        assertEquals(42.0, provider.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
        assertEquals("cli", provider.defaultAccount.answeredBy)
    }

    @Test
    fun `should refresh Claude in the background no more than every 15 minutes in API mode, even when the person picked 1 minute (#204)`() = runTest {
        val provider = claude.provider(settings = InMemoryProviderSettings(dataSourceKinds = mapOf("claude" to "api")))
        val clock = RecordingClock()
        val monitor = products.monitor(provider, clock = clock, scope = backgroundScope)

        monitor.startMonitoring(60.0, listOf("claude")).toList()

        assertEquals(listOf(900.0), clock.durations.toList())
    }

    @Test
    fun `should show fresh quotas on every Refresh click in API mode, despite the 15-minute background floor (#204)`() = runTest {
        // A different answer on each fetch. No cache here: Claude's API keeps its usage 15 minutes,
        // and that is the data source's own law, not the Monitor's.
        val usage = StubUsage { asked -> listOf(session(if (asked == 1) 80.0 else 60.0)) }
        val provider = products.product("claude", usage)
        val monitor = products.monitor(provider)

        monitor.refresh("claude")
        assertEquals(80.0, provider.defaultAccount.snapshot?.sessionQuota?.percentRemaining)

        monitor.refresh("claude")
        assertEquals(60.0, provider.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
    }
}
