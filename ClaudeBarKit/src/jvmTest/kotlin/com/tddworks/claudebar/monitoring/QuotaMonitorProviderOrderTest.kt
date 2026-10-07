package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.InMemoryProviderSettings
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** #141: the popover pills, the overview and ⌘1–⌘9 follow the person's saved provider order, not the registration order. */
class QuotaMonitorProviderOrderTest {
    private val products = StubbedProducts()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    /** Registered [claude, codex, gemini]; the order is `Providers`' (TARGET §2.1) and the Monitor shows it. */
    private fun monitor(order: List<String> = emptyList(), turnedOff: String? = null): QuotaMonitor {
        val settings = InMemoryProviderSettings().apply { setProviderOrder(order) }
        val providers = products.kept(listOf("claude", "codex", "gemini").map { products.product(it, settings = settings) }, settings)
        turnedOff?.let { providers.provider(it)?.isEnabled = false }
        return QuotaMonitor(providers, settingsRepository = settings)
    }

    // Reading the saved order

    @Test
    fun `should list the providers in registration order when the person never reordered them`() {
        val monitor = monitor()

        assertEquals(listOf("claude", "codex", "gemini"), monitor.lineup.map { it.id })
        assertEquals(listOf("claude", "codex", "gemini"), monitor.logins.map { it.id })
    }

    @Test
    fun `should show the lineup in the person's saved order (#141)`() {
        val monitor = monitor(listOf("gemini", "claude", "codex"))

        assertEquals(listOf("gemini", "claude", "codex"), monitor.lineup.map { it.id })
    }

    @Test
    fun `should list every login in the person's saved order (#141)`() {
        val monitor = monitor(listOf("gemini", "claude", "codex"))

        assertEquals(listOf("gemini", "claude", "codex"), monitor.logins.map { it.id })
    }

    @Test
    fun `should place a provider missing from the saved order at its registration position`() {
        // "gone" was removed from the app; claude and codex aren't listed, so they keep their order behind gemini.
        val monitor = monitor(listOf("gemini", "gone"))

        assertEquals(listOf("gemini", "claude", "codex"), monitor.logins.map { it.id })
    }

    @Test
    fun `should leave a disabled provider out of the lineup while still listing its login in the saved order`() {
        val monitor = monitor(listOf("gemini", "claude", "codex"), turnedOff = "codex")

        assertEquals(listOf("gemini", "claude"), monitor.lineup.map { it.id })
        assertEquals(listOf("gemini", "claude", "codex"), monitor.logins.map { it.id })
    }

    // Keyboard selection follows the saved order

    @Test
    fun `should select providers with ⌘1–⌘3 in the person's saved order`() {
        val monitor = monitor(listOf("gemini", "claude", "codex"))

        monitor.selectProvider(atPosition = 1)
        assertEquals("gemini", monitor.selectedProviderId)

        monitor.selectProvider(atPosition = 2)
        assertEquals("claude", monitor.selectedProviderId)

        monitor.selectProvider(atPosition = 3)
        assertEquals("codex", monitor.selectedProviderId)
    }

    @Test
    fun `should land ⌘1 on the first enabled provider when the first saved one is disabled`() {
        val monitor = monitor(listOf("gemini", "claude", "codex"), turnedOff = "gemini")

        monitor.selectProvider(atPosition = 1)

        assertEquals("claude", monitor.selectedProviderId)
    }

    // Reordering

    @Test
    fun `should show and select a moved provider at its new position`() {
        val monitor = monitor()

        monitor.providers.move("gemini", -2)

        assertEquals(listOf("gemini", "claude", "codex"), monitor.lineup.map { it.id })
        monitor.selectProvider(atPosition = 1)
        assertEquals("gemini", monitor.selectedProviderId)
    }
}
