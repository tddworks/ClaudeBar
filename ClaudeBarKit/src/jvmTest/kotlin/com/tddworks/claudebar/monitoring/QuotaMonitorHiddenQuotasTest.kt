package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.InMemoryProviderSettings
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * #140: hidden quota keys stop driving the monitor's aggregates — the lowest quota, the overall
 * status, the selected provider's status and alerts. A hidden "Gemini Flash 2.0" must not colour
 * the provider.
 */
class QuotaMonitorHiddenQuotasTest {
    private val products = StubbedProducts()
    private val flash = QuotaType.ModelSpecific("gemini-2.0-flash")

    @AfterEach
    fun cleanUp() = products.cleanUp()

    /** Session and weekly healthy, the flash model critical (10%). */
    private fun geminiUsage() = StubUsage.of(
        StubQuota("session", 80.0),
        StubQuota("weekly", 70.0),
        StubQuota("model:gemini-2.0-flash", 10.0),
    )

    private fun settings(hiddenKeys: Set<String>) = InMemoryProviderSettings().apply { setHiddenQuotaKeys(hiddenKeys, "gemini") }

    private suspend fun refreshedGeminiMonitor(hiddenKeys: Set<String>, alerter: QuotaAlerter? = null): Pair<QuotaMonitor, InMemoryProviderSettings> {
        val settings = settings(hiddenKeys)
        val gemini = products.product("gemini", geminiUsage(), settings)
        val monitor = QuotaMonitor(products.kept(listOf(gemini)), alerter, settingsRepository = settings)
        monitor.refresh("gemini")
        return monitor to settings
    }

    // Lowest quota

    @Test
    fun `should headline the lowest quota the person can see, not a hidden one (#140)`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"))

        // The headline number moves to the next-lowest visible quota…
        assertEquals(QuotaType.Weekly, monitor.lowestQuota()?.quotaType)

        // …and the same usage without hiding picks the flash model.
        val (unhidden, _) = refreshedGeminiMonitor(emptySet())
        assertEquals(flash, unhidden.lowestQuota()?.quotaType)
    }

    @Test
    fun `should show every quota rather than nothing when settings hide them all`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("session", "weekly", "model:gemini-2.0-flash"))

        assertEquals(flash, monitor.lowestQuota()?.quotaType)
    }

    // One usage for every surface

    @Test
    fun `should leave a hidden quota out of the usage everywhere shows, while keeping it read`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"))
        val gemini = monitor.login("gemini")!!

        val usage = monitor.usage(gemini)!!

        assertEquals(listOf(QuotaType.Session, QuotaType.Weekly), usage.quotas.map { it.quotaType })
        assertEquals(3, gemini.snapshot?.quotas?.size)
    }

    @Test
    fun `should leave a quota out and stop it colouring the status at once when the person hides it`() = runTest {
        val (monitor, settings) = refreshedGeminiMonitor(emptySet())
        val gemini = monitor.login("gemini")!!

        assertTrue(monitor.setQuota("model:gemini-2.0-flash", hidden = true, of = gemini))

        assertEquals(setOf("model:gemini-2.0-flash"), monitor.hiddenQuotaKeys(gemini))
        assertEquals(setOf("model:gemini-2.0-flash"), settings.hiddenQuotaKeys("gemini"))
        assertEquals(QuotaStatus.HEALTHY, monitor.overallStatus)
        assertEquals(2, monitor.usage(gemini)?.quotas?.size)
    }

    @Test
    fun `should refuse to hide the last quota the person can see`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("session", "weekly"))
        val gemini = monitor.login("gemini")!!

        assertFalse(monitor.setQuota("model:gemini-2.0-flash", hidden = true, of = gemini))

        assertEquals(setOf("session", "weekly"), monitor.hiddenQuotaKeys(gemini))
        assertEquals(listOf(flash), monitor.usage(gemini)?.quotas?.map { it.quotaType })
    }

    @Test
    fun `should bring a quota back, status and all, when the person shows it again`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"))
        val gemini = monitor.login("gemini")!!

        assertTrue(monitor.setQuota("model:gemini-2.0-flash", hidden = false, of = gemini))

        assertTrue(monitor.hiddenQuotaKeys(gemini).isEmpty())
        assertEquals(QuotaStatus.CRITICAL, monitor.overallStatus)
    }

    @Test
    fun `should count every quota when there are no saved settings`() = runTest {
        val gemini = products.product("gemini", geminiUsage(), settings(emptySet()))
        val monitor = QuotaMonitor(products.kept(listOf(gemini)))

        monitor.refresh("gemini")

        assertEquals(flash, monitor.lowestQuota()?.quotaType)
        assertEquals(QuotaStatus.CRITICAL, monitor.overallStatus)
    }

    // Overall status

    @Test
    fun `should keep the menu bar healthy when only a hidden quota is critical`() = runTest {
        val (hidden, _) = refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"))
        assertEquals(QuotaStatus.HEALTHY, hidden.overallStatus)

        val (visible, _) = refreshedGeminiMonitor(emptySet())
        assertEquals(QuotaStatus.CRITICAL, visible.overallStatus)
    }

    @Test
    fun `should keep the selected provider healthy when only a hidden quota is critical`() = runTest {
        val (monitor, _) = refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"))

        assertEquals("gemini", monitor.selectedProviderId)
        assertEquals(QuotaStatus.HEALTHY, monitor.selectedProviderStatus)
    }

    // Alerts

    @Test
    fun `should not alert the person when only a hidden quota turns critical`() = runTest {
        val alerter = RecordingAlerter()

        refreshedGeminiMonitor(setOf("model:gemini-2.0-flash"), alerter)

        // The visible status is healthy, as before the refresh: nothing to alert about.
        assertTrue(alerter.alerts.isEmpty())
    }

    @Test
    fun `should alert the person when a quota they can see turns critical`() = runTest {
        val alerter = RecordingAlerter()

        refreshedGeminiMonitor(emptySet(), alerter)

        assertEquals(listOf(RecordingAlerter.Alert("gemini", QuotaStatus.HEALTHY, QuotaStatus.CRITICAL)), alerter.alerts.toList())
    }
}
