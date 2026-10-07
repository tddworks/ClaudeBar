package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.InMemoryProviderSettings
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.StatusPolicy
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Collections
import kotlin.coroutines.cancellation.CancellationException

class QuotaMonitorTest {
    /** Waits the time it is asked, in the test's virtual time. */
    private object VirtualClock : Clock {
        override suspend fun sleep(seconds: Double) = delay((seconds * 1000).toLong())
    }

    /** Waits until the loop is stopped: one cycle runs, then the loop parks here. */
    private object SuspendingClock : Clock {
        override suspend fun sleep(seconds: Double): Unit = awaitCancellation()
    }

    /** Records each wait, then ends the loop — one tick runs, and its cadence can be read. */
    private class RecordingClock : Clock {
        val durations: MutableList<Double> = Collections.synchronizedList(mutableListOf())

        override suspend fun sleep(seconds: Double) {
            durations += seconds
            throw CancellationException("one tick")
        }
    }

    /** A power state the test controls; [parked] completes once the loop has read it asleep. */
    private class FakePowerState(asleep: Boolean = false, override val isOnBattery: Boolean = false) : PowerStateProvider {
        @Volatile private var asleep = asleep
        private val transitions = Channel<PowerEvent>(Channel.UNLIMITED)
        val parked = CompletableDeferred<Unit>()

        override val isDisplayAsleep: Boolean
            get() = asleep.also { if (it) parked.complete(Unit) }

        override fun events(): Flow<PowerEvent> = transitions.receiveAsFlow()

        fun wake() {
            asleep = false
            transitions.trySend(PowerEvent.DID_WAKE)
        }
    }

    private val products = StubbedProducts()
    private val settings = InMemoryProviderSettings()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    private fun product(id: String, usage: StubUsage = StubUsage.unused(), available: Boolean = true): Provider =
        products.product(id, usage, settings, available)

    private fun session(percentRemaining: Double) = StubQuota("session", percentRemaining)

    private fun monitor(
        vararg kept: Provider,
        alerter: QuotaAlerter? = null,
        clock: Clock = VirtualClock,
        powerState: PowerStateProvider? = null,
        statusPolicy: () -> StatusPolicy = { StatusPolicy.Absolute },
        scope: CoroutineScope? = null,
    ): QuotaMonitor {
        val providers = products.kept(kept.toList())
        return if (scope == null) {
            QuotaMonitor(providers, alerter, clock, powerState = powerState, statusPolicy = statusPolicy)
        } else {
            QuotaMonitor(providers, alerter, clock, powerState = powerState, statusPolicy = statusPolicy, scope = scope)
        }
    }

    /** A monitor whose background loop runs in the test's virtual time and ends with it. */
    private fun TestScope.looping(vararg kept: Provider, clock: Clock = VirtualClock, powerState: PowerStateProvider? = null) =
        monitor(*kept, clock = clock, powerState = powerState, scope = backgroundScope)

    // After a refresh: the one extension point

    @Test
    fun `should tell every listener, in turn, about each login that refreshed`() = runTest {
        val monitor = monitor(product("claude", StubUsage.of()))
        val heard = Collections.synchronizedList(mutableListOf<String>())
        monitor.onRefreshed { heard += "first:${it.id}" }
        monitor.onRefreshed { heard += "second:${it.id}" }

        monitor.refresh("claude")

        assertEquals(listOf("first:claude", "second:claude"), heard.toList())
    }

    @Test
    fun `should tell no listener when the login's refresh fails`() = runTest {
        val monitor = monitor(product("claude", StubUsage.failing()))
        var heard = 0
        monitor.onRefreshed { heard += 1 }

        monitor.refresh("claude")

        assertEquals(0, heard)
    }

    @Test
    fun `should show a provider's session and weekly quotas after refreshing it`() = runTest {
        val claude = product("claude", StubUsage.of(session(65.0), StubQuota("weekly", 35.0)))
        val monitor = monitor(claude)

        monitor.refresh("claude")

        val snapshot = claude.defaultAccount.snapshot
        assertNotNull(snapshot)
        assertEquals(2, snapshot?.quotas?.size)
        assertEquals(65.0, snapshot?.quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should show no quotas for a provider that is not available`() = runTest {
        val claude = product("claude", StubUsage.of(session(65.0)), available = false)
        val monitor = monitor(claude)

        monitor.refreshAll()

        assertNull(claude.defaultAccount.snapshot)
    }

    // Several providers

    @Test
    fun `should show every provider's quotas after refreshing all`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codex = product("codex", StubUsage.of(session(40.0)))
        val monitor = monitor(claude, codex)

        monitor.refreshAll()

        assertEquals(70.0, claude.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
        assertEquals(40.0, codex.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
    }

    @Test
    fun `should still show the other providers' quotas when one provider fails`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codex = product("codex", StubUsage.failing())
        val monitor = monitor(claude, codex)

        monitor.refreshAll()

        assertNotNull(claude.defaultAccount.snapshot)
        assertNull(codex.defaultAccount.snapshot)
        assertNotNull(codex.defaultAccount.lastError)
    }

    // Refresh others

    @Test
    fun `should refresh every provider but the one just refreshed`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codex = product("codex", StubUsage.of(session(50.0)))
        val gemini = product("gemini", StubUsage.of(session(30.0)))
        val monitor = monitor(claude, codex, gemini)

        monitor.refreshOthers(except = "claude")

        assertNull(claude.defaultAccount.snapshot)
        assertEquals(50.0, codex.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
        assertEquals(30.0, gemini.defaultAccount.snapshot?.sessionQuota?.percentRemaining)
    }

    // Finding a login

    @Test
    fun `should find a login by its provider's id`() {
        val monitor = monitor(product("claude"))

        assertEquals("claude", monitor.login("claude")?.id)
    }

    @Test
    fun `should find no login for an unknown provider id`() {
        val monitor = monitor()

        assertNull(monitor.login("unknown"))
    }

    // Overall status

    @Test
    fun `should take the worst provider's status as the overall status`() = runTest {
        val monitor = monitor(product("claude", StubUsage.of(session(70.0))), product("codex", StubUsage.of(session(15.0))))

        monitor.refreshAll()

        assertEquals(QuotaStatus.CRITICAL, monitor.overallStatus)
    }

    // Refresh selected

    @Test
    fun `should refresh only the selected provider`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codex = product("codex", StubUsage.of(session(40.0)))
        val monitor = monitor(claude, codex)

        monitor.refreshSelected()

        assertNotNull(claude.defaultAccount.snapshot)
        assertNull(codex.defaultAccount.snapshot)
    }

    @Test
    fun `should refresh the provider the person just switched to`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codex = product("codex", StubUsage.of(session(40.0)))
        val monitor = monitor(claude, codex)

        monitor.selectProvider("codex")
        monitor.refreshSelected()

        assertNull(claude.defaultAccount.snapshot)
        assertNotNull(codex.defaultAccount.snapshot)
    }

    // Continuous monitoring

    @Test
    fun `should report each background refresh while monitoring runs`() = runTest {
        val monitor = looping(product("claude", StubUsage.of(session(50.0))))

        val events = monitor.startMonitoring(intervalSeconds = 0.1).take(2).toList()
        monitor.stopMonitoring()

        assertEquals(listOf(MonitoringEvent.Refreshed, MonitoringEvent.Refreshed), events)
    }

    @Test
    fun `should refresh the selected provider and the menu bar's providers in the background`() = runTest {
        val claudeUsage = StubUsage.counting()
        val codexUsage = StubUsage.counting()
        val claude = product("claude", claudeUsage)
        val codex = product("codex", codexUsage)
        val monitor = looping(claude, codex, clock = SuspendingClock)

        monitor.startMonitoring(60.0, listOf("claude", "codex")).take(1).toList()
        monitor.stopMonitoring()

        assertEquals(1, claudeUsage.count)
        assertEquals(1, codexUsage.count)
        assertNotNull(claude.defaultAccount.snapshot)
        assertNotNull(codex.defaultAccount.snapshot)
    }

    @Test
    fun `should refresh a provider once in the background when it is both selected and in the menu bar`() = runTest {
        val usage = StubUsage.counting()
        val monitor = looping(product("claude", usage), clock = SuspendingClock)

        monitor.startMonitoring(60.0, listOf("claude", "claude")).take(1).toList()
        monitor.stopMonitoring()

        assertEquals(1, usage.count)
    }

    @Test
    fun `should refresh only the selected provider in the background when the menu bar names none`() = runTest {
        val claudeUsage = StubUsage.counting()
        val codexUsage = StubUsage.counting()
        val monitor = looping(product("claude", claudeUsage), product("codex", codexUsage), clock = SuspendingClock)
        monitor.selectProvider("codex")

        monitor.startMonitoring(60.0).take(1).toList()
        monitor.stopMonitoring()

        assertEquals(0, claudeUsage.count)
        assertEquals(1, codexUsage.count)
    }

    @Test
    fun `should stop reporting refreshes once monitoring is stopped`() = runTest {
        val monitor = looping(product("claude", StubUsage.of(session(50.0))))

        val events = monitor.startMonitoring(intervalSeconds = 0.05)
        monitor.stopMonitoring()

        assertTrue(events.toList().size <= 2)
    }

    @Test
    fun `should show monitoring on while it runs and off once stopped, on the main actor (#182)`() = runTest {
        val monitor = looping(product("claude", StubUsage.counting()), clock = SuspendingClock)

        val events = monitor.startMonitoring(60.0)
        assertTrue(monitor.isMonitoring)

        events.take(1).toList()
        monitor.stopMonitoring()

        assertFalse(monitor.isMonitoring)
    }

    @Test
    fun `should never refresh more often than once a minute (#67)`() {
        assertEquals(60.0, QuotaMonitor.clampedInterval(5.0))
        assertEquals(60.0, QuotaMonitor.clampedInterval(0.0))
        assertEquals(60.0, QuotaMonitor.clampedInterval(60.0))
        assertEquals(300.0, QuotaMonitor.clampedInterval(300.0))
        assertEquals(900.0, QuotaMonitor.clampedInterval(900.0))
    }

    @Test
    fun `should slow the refresh to the slowest provider's minimum, like Claude API's 15 minutes (#204)`() {
        // No provider floor: the clamped request.
        assertEquals(600.0, QuotaMonitor.effectiveInterval(600.0, emptyList()))
        assertEquals(60.0, QuotaMonitor.effectiveInterval(5.0, emptyList()))
        // A floor under the requested cadence leaves it.
        assertEquals(600.0, QuotaMonitor.effectiveInterval(600.0, listOf(60.0)))
        // A 15-minute floor lifts even the 1-minute option.
        assertEquals(900.0, QuotaMonitor.effectiveInterval(60.0, listOf(900.0)))
        assertEquals(900.0, QuotaMonitor.effectiveInterval(600.0, listOf(900.0)))
        // The slowest floor wins for a mixed set.
        assertEquals(900.0, QuotaMonitor.effectiveInterval(60.0, listOf(300.0, 900.0)))
    }

    // Energy awareness (#204)

    @Test
    fun `should not refresh while the display sleeps, and refresh once on wake (#204)`() = runTest {
        val usage = StubUsage.counting()
        val power = FakePowerState(asleep = true)
        val monitor = looping(product("claude", usage), clock = RecordingClock(), powerState = power)

        val events = monitor.startMonitoring(60.0)

        // The loop reaches the asleep gate and parks — no refresh while asleep.
        power.parked.await()
        assertEquals(0, usage.count)

        // Waking lets exactly one refresh through, then the clock ends the loop.
        power.wake()
        events.toList()
        assertEquals(1, usage.count)
    }

    @Test
    fun `should refresh half as often on battery (#204)`() = runTest {
        val clock = RecordingClock()
        val monitor = looping(product("claude", StubUsage.counting()), clock = clock, powerState = FakePowerState(isOnBattery = true))

        monitor.startMonitoring(600.0).toList()

        // 600s → 1200s on battery; the stub declares no provider floor.
        assertEquals(listOf(1200.0), clock.durations.toList())
    }

    @Test
    fun `should refresh at the chosen cadence on AC power`() = runTest {
        val clock = RecordingClock()
        val monitor = looping(product("claude", StubUsage.counting()), clock = clock, powerState = FakePowerState(isOnBattery = false))

        monitor.startMonitoring(600.0).toList()

        assertEquals(listOf(600.0), clock.durations.toList())
    }

    // The logins

    @Test
    fun `should list every registered login`() {
        val monitor = monitor(product("claude"), product("codex"))

        assertEquals(2, monitor.logins.size)
    }

    @Test
    fun `should show only enabled logins in the lineup`() {
        val claude = product("claude")
        val codex = product("codex")
        codex.defaultAccount.isEnabled = false
        val monitor = monitor(claude, codex)

        assertEquals(listOf("claude"), monitor.lineup.map { it.id })
    }

    // Lowest quota

    @Test
    fun `should find the lowest quota across every provider`() = runTest {
        val monitor = monitor(product("claude", StubUsage.of(session(70.0))), product("codex", StubUsage.of(session(25.0))))

        monitor.refreshAll()

        assertEquals(25.0, monitor.lowestQuota()?.percentRemaining)
    }

    @Test
    fun `should find no lowest quota before any provider has quotas`() {
        val monitor = monitor(product("claude"))

        assertNull(monitor.lowestQuota())
    }

    // Selection

    @Test
    fun `should show the login of the selected provider`() {
        val monitor = monitor(product("claude"), product("codex"))

        monitor.selectedProviderId = "codex"

        assertEquals("codex", monitor.selectedLogin?.id)
    }

    @Test
    fun `should show no selected login when the selected provider is disabled`() {
        val claude = product("claude")
        claude.defaultAccount.isEnabled = false
        val monitor = monitor(claude)
        monitor.selectedProviderId = "claude"

        assertNull(monitor.selectedLogin)
    }

    @Test
    fun `should show the selected provider as healthy before its quotas arrive`() {
        val monitor = monitor(product("claude"))

        assertEquals(QuotaStatus.HEALTHY, monitor.selectedProviderStatus)
    }

    @Test
    fun `should show the selected provider's status once its quotas arrive`() = runTest {
        val monitor = monitor(product("claude", StubUsage.of(session(15.0))))

        monitor.refresh("claude")

        assertEquals(QuotaStatus.CRITICAL, monitor.selectedProviderStatus)
    }

    @Test
    fun `should show the selected tab awaiting data, then critical once its login's usage arrives`() = runTest {
        val claude = product("claude", StubUsage.of(session(15.0)))
        val monitor = monitor(claude)
        assertEquals(listOf("claude"), monitor.selectedLogins.map { it.id })
        assertNull(monitor.selectedTabStatus)
        assertEquals(ProviderBadgeState.AwaitingData, monitor.selectedBadge)
        assertNull(monitor.status(claude.defaultAccount))

        monitor.refresh("claude")

        assertEquals(QuotaStatus.CRITICAL, monitor.selectedTabStatus)
        assertEquals(ProviderBadgeState.Quota(QuotaStatus.CRITICAL), monitor.selectedBadge)
        assertEquals(QuotaStatus.CRITICAL, monitor.status(claude.defaultAccount))
    }

    @Test
    fun `should select an enabled provider the person picks`() {
        val monitor = monitor(product("claude"), product("codex"))
        assertEquals("claude", monitor.selectedProviderId)

        monitor.selectProvider("codex")

        assertEquals("codex", monitor.selectedProviderId)
    }

    @Test
    fun `should keep the current selection when the person picks a disabled provider`() {
        val codex = product("codex")
        codex.defaultAccount.isEnabled = false
        val monitor = monitor(product("claude"), codex)

        monitor.selectProvider("codex")

        assertEquals("claude", monitor.selectedProviderId)
    }

    @Test
    fun `should select the enabled provider shown in the pill slot, skipping disabled ones`() {
        // Gemini sits between two enabled providers but is off, so the pills read: 1 Claude, 2 Codex.
        val gemini = product("gemini")
        gemini.defaultAccount.isEnabled = false
        val monitor = monitor(product("claude"), gemini, product("codex"))

        monitor.selectProvider(atPosition = 2)

        assertEquals("codex", monitor.selectedProviderId)
    }

    @Test
    fun `should keep the current selection when the shortcut's slot has no provider`() {
        val monitor = monitor(product("claude"), product("codex"))

        monitor.selectProvider(atPosition = 3)
        monitor.selectProvider(atPosition = 0)

        assertEquals("claude", monitor.selectedProviderId)
    }

    @Test
    fun `should select the first enabled provider at launch when Claude is disabled`() {
        val claude = product("claude")
        claude.defaultAccount.isEnabled = false

        val monitor = monitor(claude, product("codex"))

        assertEquals("codex", monitor.selectedProviderId)
    }

    @Test
    fun `should select Claude at launch when it is enabled`() {
        val monitor = monitor(product("claude"), product("codex"))

        assertEquals("claude", monitor.selectedProviderId)
    }

    // Refreshing state

    @Test
    fun `should not show refreshing when no provider is syncing`() {
        val monitor = monitor(product("claude"))

        assertFalse(monitor.isRefreshing)
    }

    // The providers it keeps

    @Test
    fun `should list the logins of the providers the app keeps`() {
        val monitor = monitor(product("claude"), product("codex"))

        assertEquals(2, monitor.logins.size)
    }

    // Alerts

    @Test
    fun `should alert when a provider turns critical`() = runTest {
        val alerter = RecordingAlerter()
        val monitor = monitor(product("claude", StubUsage.of(session(15.0))), alerter = alerter)

        monitor.refresh("claude")

        assertEquals(listOf(RecordingAlerter.Alert("claude", QuotaStatus.HEALTHY, QuotaStatus.CRITICAL)), alerter.alerts.toList())
    }

    @Test
    fun `should not alert when a provider's status stays healthy`() = runTest {
        val alerter = RecordingAlerter()
        val monitor = monitor(product("claude", StubUsage.of(session(70.0))), alerter = alerter)

        monitor.refresh("claude")
        monitor.refresh("claude")

        assertTrue(alerter.alerts.isEmpty())
    }

    @Test
    fun `should neither warn nor alert for an on-pace quota when status is pace-aware`() = runTest {
        // 40% left with 90% of the 5-hour window gone: on pace, so healthy.
        val alerter = RecordingAlerter()
        val monitor = monitor(
            product("claude", StubUsage.of(StubQuota("session", 40.0, resetsInSeconds = 30 * 60.0))),
            alerter = alerter,
            statusPolicy = { StatusPolicy.PaceAware(burnRateThreshold = 1.5) },
        )

        monitor.refresh("claude")

        // The notification agrees with the menu bar: no warning.
        assertTrue(alerter.alerts.isEmpty())
        assertEquals(QuotaStatus.HEALTHY, monitor.selectedProviderStatus)
    }

    @Test
    fun `should alert a warning for the same quota when status is absolute`() = runTest {
        val alerter = RecordingAlerter()
        val monitor = monitor(
            product("claude", StubUsage.of(StubQuota("session", 40.0, resetsInSeconds = 30 * 60.0))),
            alerter = alerter,
            statusPolicy = { StatusPolicy.Absolute },
        )

        monitor.refresh("claude")

        assertEquals(listOf(RecordingAlerter.Alert("claude", QuotaStatus.HEALTHY, QuotaStatus.WARNING)), alerter.alerts.toList())
    }

    // Disabled providers

    @Test
    fun `should not refresh a disabled provider`() = runTest {
        val claude = product("claude", StubUsage.of(session(70.0)))
        val codexUsage = StubUsage.of(session(40.0))
        val codex = product("codex", codexUsage)
        codex.defaultAccount.isEnabled = false
        val monitor = monitor(claude, codex)

        monitor.refreshAll()

        assertNotNull(claude.defaultAccount.snapshot)
        assertNull(codex.defaultAccount.snapshot)
        assertEquals(0, codexUsage.count)
    }

    @Test
    fun `should leave a disabled provider out of the overall status`() = runTest {
        val codex = product("codex", StubUsage.of(session(5.0)))
        val monitor = monitor(product("claude", StubUsage.of(session(70.0))), codex)

        monitor.refreshAll()
        assertEquals(QuotaStatus.CRITICAL, monitor.overallStatus)

        codex.defaultAccount.isEnabled = false

        assertEquals(QuotaStatus.HEALTHY, monitor.overallStatus)
    }

    // A login's own switch

    @Test
    fun `should select the next enabled provider when the person disables the selected one`() {
        val claude = product("claude")
        val monitor = monitor(claude, product("codex"))
        monitor.selectedProviderId = "claude"

        monitor.setProviderEnabled("claude", enabled = false)

        assertFalse(claude.defaultAccount.isEnabled)
        assertEquals("codex", monitor.selectedProviderId)
    }

    @Test
    fun `should keep the selection when the person enables another provider`() {
        val codex = product("codex")
        codex.defaultAccount.isEnabled = false
        val monitor = monitor(product("claude"), codex)
        monitor.selectedProviderId = "claude"

        monitor.setProviderEnabled("codex", enabled = true)

        assertTrue(codex.defaultAccount.isEnabled)
        assertEquals("claude", monitor.selectedProviderId)
    }
}
