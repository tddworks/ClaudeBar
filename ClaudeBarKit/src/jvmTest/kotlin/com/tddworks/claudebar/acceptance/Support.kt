package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.monitoring.Clock
import com.tddworks.claudebar.monitoring.QuotaAlerter
import com.tddworks.claudebar.monitoring.QuotaMonitor
import com.tddworks.claudebar.monitoring.StubQuota
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.JsonProviderSettings
import com.tddworks.claudebar.providers.MemoryLegacyStore
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.temporarySettingsFile
import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import java.util.Collections
import kotlin.coroutines.cancellation.CancellationException

// What the acceptance specs stand on, as the Swift specs' Support/ folder did: stubbed products
// (monitoring/StubbedProduct.kt), the real bundled definitions over stubbed connections
// (providers/StubbedProvider.kt, ClaudeHarness.kt), and the clocks a background loop waits on.

/** Waits the time it is asked, in the test's virtual time. */
internal object VirtualClock : Clock {
    override suspend fun sleep(seconds: Double) = delay((seconds * 1000).toLong())
}

/** Waits until the loop is stopped: one cycle runs, then the loop parks here. */
internal object SuspendingClock : Clock {
    override suspend fun sleep(seconds: Double): Unit = awaitCancellation()
}

/** Records each wait, then ends the loop — one tick runs, and its cadence can be read. */
internal class RecordingClock : Clock {
    val durations: MutableList<Double> = Collections.synchronizedList(mutableListOf())

    override suspend fun sleep(seconds: Double) {
        durations += seconds
        throw CancellationException("one tick")
    }
}

/** One session quota with [percentRemaining] left, as a stubbed product answers it. */
internal fun session(percentRemaining: Double) = StubQuota("session", percentRemaining)

/** A monitor over [kept], in the order given; its background loop runs in [scope] when one is given. */
internal fun StubbedProducts.monitor(
    vararg kept: Provider,
    alerter: QuotaAlerter? = null,
    clock: Clock = VirtualClock,
    scope: CoroutineScope? = null,
): QuotaMonitor {
    val providers = kept(kept.toList())
    return if (scope == null) QuotaMonitor(providers, alerter, clock) else QuotaMonitor(providers, alerter, clock, scope = scope)
}

/** The settings the app keeps, in a settings.json of its own — never the person's. */
internal class IsolatedSettings {
    val file: SettingsFile = temporarySettingsFile()
    val repository = JsonProviderSettings(file, MemoryLegacyStore())

    /** The same settings.json read again, as after a relaunch. */
    fun reopened() = JsonProviderSettings(SettingsFile(file.path), MemoryLegacyStore())
}
