package com.tddworks.claudebar.monitoring

import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import platform.AppKit.NSWorkspaceDidWakeNotification
import platform.AppKit.NSWorkspaceScreensDidSleepNotification
import platform.Foundation.NSNotificationCenter
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SystemPowerStateProviderTest {
    /** A center of its own, so the test posts the workspace's notifications without touching the real one. */
    private val center = NSNotificationCenter()

    @Test
    fun `should say the display is awake until the Mac says it sleeps`() {
        val power = SystemPowerStateProvider(center)

        assertFalse(power.isDisplayAsleep)
        power.close()
    }

    @Test
    fun `should say the display sleeps once its screens sleep and wakes again on wake`() = runBlocking {
        val power = SystemPowerStateProvider(center)
        val events = power.events()

        center.postNotificationName(NSWorkspaceScreensDidSleepNotification, null)
        assertTrue(power.isDisplayAsleep)
        center.postNotificationName(NSWorkspaceDidWakeNotification, null)
        assertFalse(power.isDisplayAsleep)

        assertEquals(listOf(PowerEvent.WILL_SLEEP, PowerEvent.DID_WAKE), events.take(2).toList())
        power.close()
    }

    @Test
    fun `should read whether the Mac runs on battery without failing`() {
        val power = SystemPowerStateProvider(center)

        // Either answer is right on this Mac; reading IOKit's power sources must not crash.
        power.isOnBattery
        power.close()
    }

    @Test
    fun `should wait the time the system clock is asked`() = runBlocking {
        SystemClock.sleep(0.01)
    }
}
