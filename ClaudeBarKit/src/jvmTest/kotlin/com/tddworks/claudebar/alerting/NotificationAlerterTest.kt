package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.QuotaStatus
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

internal class NotificationAlerterTest {
    private class Sent(private val failing: Boolean = false, private val granted: Boolean = true) : AlertSender {
        val alerts = mutableListOf<Triple<String, String, String>>()
        var permissionAsks = 0

        override suspend fun requestPermission(): Boolean {
            permissionAsks++
            return granted
        }

        override suspend fun send(title: String, body: String, categoryIdentifier: String) {
            alerts += Triple(title, body, categoryIdentifier)
            if (failing) throw IllegalStateException("test")
        }

        override suspend fun send(title: String, body: String, categoryIdentifier: String, button: String, link: String) = Unit
    }

    /** The names a lineup gives: each built-in definition's profile name, as the composition root answers. */
    private val definitionNames = LineupNames { providerId ->
        File("definitions/$providerId.json").takeIf { it.exists() }
            ?.let { Json.parseToJsonElement(it.readText()).jsonObject["profile"]?.jsonObject?.get("name")?.jsonPrimitive?.content }
    }

    private fun alerter(sender: AlertSender = Sent()) = NotificationAlerter(sender, definitionNames)

    // Should alert

    @Test
    fun `should alert when a quota is at warning`() {
        assertTrue(alerter().shouldAlert(QuotaStatus.WARNING))
    }

    @Test
    fun `should alert when a quota is critical`() {
        assertTrue(alerter().shouldAlert(QuotaStatus.CRITICAL))
    }

    @Test
    fun `should alert when a quota is depleted`() {
        assertTrue(alerter().shouldAlert(QuotaStatus.DEPLETED))
    }

    @Test
    fun `should not alert when a quota is healthy`() {
        assertFalse(alerter().shouldAlert(QuotaStatus.HEALTHY))
    }

    // Provider display name

    @Test
    fun `should name each known provider as the person knows it`() {
        val alerter = alerter()

        assertEquals("Claude", alerter.providerDisplayName("claude"))
        assertEquals("Codex", alerter.providerDisplayName("codex"))
        assertEquals("Gemini", alerter.providerDisplayName("gemini"))
        assertEquals("Copilot", alerter.providerDisplayName("copilot"))
        assertEquals("Antigravity", alerter.providerDisplayName("antigravity"))
        assertEquals("Z.ai", alerter.providerDisplayName("zai"))
        assertEquals("MiniMax", alerter.providerDisplayName("minimax"))
        assertEquals("Alibaba", alerter.providerDisplayName("alibaba"))
        assertEquals("Oh My Pi", alerter.providerDisplayName("omp"))
    }

    @Test
    fun `should capitalise the id of a provider it does not know`() {
        val alerter = alerter()

        assertEquals("Unknown", alerter.providerDisplayName("unknown"))
        assertEquals("Chatgpt", alerter.providerDisplayName("chatgpt"))
    }

    // Alert body

    @Test
    fun `should say the provider is running low at warning`() {
        val body = alerter().alertBody(QuotaStatus.WARNING, "Claude")

        assertTrue("Claude" in body)
        assertTrue("running low" in body)
    }

    @Test
    fun `should say the provider is critically low when critical`() {
        val body = alerter().alertBody(QuotaStatus.CRITICAL, "Codex")

        assertTrue("Codex" in body)
        assertTrue("critically low" in body)
    }

    @Test
    fun `should say the provider is depleted when depleted`() {
        val body = alerter().alertBody(QuotaStatus.DEPLETED, "Gemini")

        assertTrue("Gemini" in body)
        assertTrue("depleted" in body)
    }

    @Test
    fun `should say the provider has recovered when healthy again`() {
        val body = alerter().alertBody(QuotaStatus.HEALTHY, "Claude")

        assertTrue("Claude" in body)
        assertTrue("recovered" in body)
    }

    // Status degradation

    @Test
    fun `should rank warning as worse than healthy`() {
        assertTrue(QuotaStatus.WARNING > QuotaStatus.HEALTHY)
    }

    @Test
    fun `should rank critical as worse than warning`() {
        assertTrue(QuotaStatus.CRITICAL > QuotaStatus.WARNING)
    }

    @Test
    fun `should rank depleted as worse than critical`() {
        assertTrue(QuotaStatus.DEPLETED > QuotaStatus.CRITICAL)
    }

    @Test
    fun `should rank healthy as better than warning`() {
        assertTrue(QuotaStatus.HEALTHY < QuotaStatus.WARNING)
    }

    @Test
    fun `should rank a status equal to itself`() {
        assertEquals(QuotaStatus.HEALTHY, QuotaStatus.HEALTHY)
    }

    // Alerting

    @Test
    fun `should notify that the quota is running low when it drops to warning`() = runBlocking {
        val sent = Sent()

        alerter(sent).alert("claude", QuotaStatus.HEALTHY, QuotaStatus.WARNING)

        val (title, body, category) = sent.alerts.single()
        assertTrue("Quota Alert" in title)
        assertTrue("running low" in body)
        assertEquals("QUOTA_ALERT", category)
    }

    @Test
    fun `should notify that the quota is critically low when it drops to critical`() = runBlocking {
        val sent = Sent()

        alerter(sent).alert("codex", QuotaStatus.WARNING, QuotaStatus.CRITICAL)

        val (title, body, category) = sent.alerts.single()
        assertTrue("Quota Alert" in title)
        assertTrue("critically low" in body)
        assertEquals("QUOTA_ALERT", category)
    }

    @Test
    fun `should notify that the quota is depleted when it runs out`() = runBlocking {
        val sent = Sent()

        alerter(sent).alert("gemini", QuotaStatus.CRITICAL, QuotaStatus.DEPLETED)

        val (title, body, category) = sent.alerts.single()
        assertTrue("Quota Alert" in title)
        assertTrue("depleted" in body)
        assertEquals("QUOTA_ALERT", category)
    }

    @Test
    fun `should not notify when the quota recovers`() = runBlocking {
        val sent = Sent()

        alerter(sent).alert("claude", QuotaStatus.WARNING, QuotaStatus.HEALTHY)

        assertTrue(sent.alerts.isEmpty())
    }

    @Test
    fun `should not notify when the quota's status stays the same`() = runBlocking {
        val sent = Sent()

        alerter(sent).alert("claude", QuotaStatus.WARNING, QuotaStatus.WARNING)

        assertTrue(sent.alerts.isEmpty())
    }

    @Test
    fun `should carry on quietly when the notification cannot be shown`() = runBlocking {
        val sent = Sent(failing = true)

        // Does not throw.
        alerter(sent).alert("claude", QuotaStatus.HEALTHY, QuotaStatus.WARNING)

        assertEquals(1, sent.alerts.size)
    }

    @Test
    fun `should grant notification permission when macOS grants it`() = runBlocking {
        val sent = Sent(granted = true)

        val result = alerter(sent).requestPermission()

        assertTrue(result)
        assertEquals(1, sent.permissionAsks)
    }
}
