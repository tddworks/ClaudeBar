package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.StatusPolicy
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.storage.CredentialRepository
import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files

/** Notify! publishing as the app runs it: what reaches the phone, and what the person is told when it can't. */
class NotifyPublisherTest {
    private val dir: File = Files.createTempDirectory("notify-publisher").toFile()
    private val settings = NotifySettings(SettingsFile(File(dir, "settings.json").path), Kept(), Kept())
    private val gateway = RecordingGateway()
    private var readings = listOf(reading(40.0))
    private var clock = 1_000_000.0

    @AfterEach
    fun cleanUp() {
        dir.deleteRecursively()
    }

    private class Kept : CredentialRepository {
        private val values = mutableMapOf<String, String>()
        override fun save(value: String, key: String) { values[key] = value }
        override fun get(key: String) = values[key]
        override fun delete(key: String) = values.remove(key) != null
    }

    private class RecordingGateway : NotifyPublishing {
        val tiles = mutableListOf<String?>()
        val gauges = mutableListOf<String?>()
        var tileFails: NotifyPublishError? = null
        override suspend fun publishTile(tile: NotifyTile, link: NotifyDeviceLink, activityId: String?): String {
            tiles += activityId
            tileFails?.let { tileFails = null; throw it }
            return "activity-1"
        }
        override suspend fun publishGauge(gauge: NotifyGauge, link: NotifyDeviceLink, widgetId: String?): String {
            gauges += widgetId
            return "widget-1"
        }
        override suspend fun publishScreenTile(tile: NotifyTile, link: NotifyDeviceLink, screenWidgetId: String?) = "screen-1"
        override suspend fun endTile(link: NotifyDeviceLink, activityId: String, keepForSeconds: Double) = Unit
        override suspend fun deviceInfo(link: NotifyDeviceLink) = NotifyDeviceInfo(link.deviceId, "Apollo", "iOS")
    }

    private fun reading(left: Double) = NotifyQuotaReading(
        "claude", "Claude",
        UsageQuota(left, QuotaType.Session, "claude", null, null, null, null, null, null, null, null, null, null),
    )

    private fun TestScope.publisher() = NotifyPublisher(
        settings, gateway, { readings }, { StatusPolicy.Absolute }, emptyFlow(), { clock }, backgroundScope,
    )

    private fun linked() {
        settings.setNotifyEnabled(true)
        settings.setNotifyLiveActivityEnabled(true)
        settings.setNotifyWidgetEnabled(true)
        settings.saveNotifyDeviceLink(requireNotNull(NotifyDeviceLink.of("IO7Q2ZKM4H2QZ1XY", "token-1")))
    }

    @Test
    fun `should tell the person publishing is off when they publish with Notify off`() = runTest {
        assertEquals("Publishing to Notify! is switched off.", publisher().publishNow())
    }

    @Test
    fun `should start a tile and keep its handle when the person publishes to a linked phone`() = runTest {
        linked()

        val failure = publisher().publishNow()

        assertNull(failure)
        assertEquals(listOf<String?>(null), gateway.tiles)
        assertEquals("activity-1", settings.notifyActivityId())
        assertEquals("widget-1", settings.notifyWidgetId())
    }

    @Test
    fun `should say no device is linked when the person publishes before linking one`() = runTest {
        settings.setNotifyEnabled(true)
        settings.setNotifyLiveActivityEnabled(true)

        assertEquals(NotifyPublishError.NotLinked.message, publisher().publishNow())
    }

    @Test
    fun `should start a fresh tile once when the phone dismissed the last one`() = runTest {
        linked()
        settings.setNotifyActivityId("dismissed")
        gateway.tileFails = NotifyPublishError.TileGone

        val failure = publisher().publishNow()

        assertNull(failure)
        assertEquals(listOf("dismissed", null), gateway.tiles)
        assertEquals("activity-1", settings.notifyActivityId())
    }

    @Test
    fun `should not write the same reading again before the tile's interval passed`() = runTest {
        linked()
        val publisher = publisher()
        publisher.offer()

        clock += 10
        publisher.offer()

        assertEquals(1, gateway.tiles.size)
    }

    @Test
    fun `should hold tile starts back while the gateway asks to wait, and keep the widget going`() = runTest {
        linked()
        val publisher = publisher()
        gateway.tileFails = NotifyPublishError.Backoff(retryAfterSeconds = 3600.0, openingTheAppMayHelp = false)
        publisher.offer()

        readings = listOf(reading(10.0))
        clock += 20 * 60
        publisher.offer()

        assertEquals(1, gateway.tiles.size)
        assertEquals(2, gateway.gauges.size)
    }

    @Test
    fun `should say there is nothing to send when no provider reported a quota yet`() = runTest {
        linked()
        readings = emptyList()

        assertEquals("There is no quota to send yet. Give a provider time to report one.", publisher().publishNow())
    }
}
