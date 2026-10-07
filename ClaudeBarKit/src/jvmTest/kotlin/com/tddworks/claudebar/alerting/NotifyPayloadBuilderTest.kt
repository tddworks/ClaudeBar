package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageQuota
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NotifyPayloadBuilderTest {
    private val builder = NotifyPayloadBuilder()
    private val now = 1_700_000_000.0

    private val healthyTint = "#59EBAD"
    private val warningTint = "#FAB859"
    private val criticalTint = "#FA6B85"

    private fun quota(
        percentRemaining: Double,
        provider: String,
        quotaType: QuotaType = QuotaType.Session,
        resetsAtSeconds: Double? = null,
        dollarRemainingNanos: Long? = null,
        compactTitle: String? = null,
    ) = UsageQuota(
        percentRemaining, quotaType, provider, resetsAtSeconds, null, null,
        dollarRemainingNanos, null, null, null, compactTitle, null, null,
    )

    private fun reading(
        percentRemaining: Double,
        provider: String = "claude",
        name: String = "Claude",
        quotaType: QuotaType = QuotaType.Session,
        resetsAtSeconds: Double? = null,
        dollarRemainingNanos: Long? = null,
        compactTitle: String? = null,
    ) = NotifyQuotaReading(
        providerId = provider,
        providerName = name,
        quota = quota(percentRemaining, provider, quotaType, resetsAtSeconds, dollarRemainingNanos, compactTitle),
    )

    private fun payload(
        readings: List<NotifyQuotaReading>,
        gaugeSelection: NotifyGaugeSelection = NotifyGaugeSelection.automatic,
        includesTile: Boolean = true,
        includesGauge: Boolean = true,
        includesScreenTile: Boolean = true,
    ) = builder.payload(readings, now, gaugeSelection, includesTile, includesGauge, includesScreenTile)

    private val twoTen = 2_100_000_000L

    // Nothing to say

    @Test
    fun `should send the phone nothing when no quota is known`() {
        val payload = payload(emptyList())

        assertEquals(NotifyPayload.empty, payload)
        assertTrue(payload.isEmpty)
        assertNull(payload.tile)
        assertNull(payload.gauge)
    }

    // The worst quota leads

    @Test
    fun `should lead the tile with the worst window, in its color`() {
        val payload = payload(
            listOf(
                reading(80.0, provider = "claude", name = "Claude", quotaType = QuotaType.Weekly),
                reading(35.0, provider = "codex", name = "Codex"),
                reading(8.0, provider = "gemini", name = "Gemini"),
            ),
        )

        assertEquals(criticalTint, payload.tile?.tintHex)
        assertEquals("Gemini 5h", payload.tile?.metrics?.first()?.label)
    }

    // Ordering

    @Test
    fun `should order windows of the same status by how little is left`() {
        val payload = payload(listOf(reading(40.0, quotaType = QuotaType.Session), reading(30.0, quotaType = QuotaType.Weekly)))

        assertEquals(listOf("30", "40"), payload.tile?.metrics?.map { it.value })
        assertEquals(warningTint, payload.tile?.tintHex)
    }

    @Test
    fun `should order windows with as much left by provider name`() {
        val payload = payload(listOf(reading(30.0, provider = "zai", name = "Z.ai"), reading(30.0, provider = "claude", name = "Claude")))

        assertEquals(listOf("Claude 5h", "Z.ai 5h"), payload.tile?.metrics?.map { it.label })
    }

    @Test
    fun `should order one provider's equal windows session before weekly`() {
        val payload = payload(listOf(reading(30.0, quotaType = QuotaType.Weekly), reading(30.0, quotaType = QuotaType.Session)))

        assertEquals(listOf("5h", "7d"), payload.tile?.metrics?.map { it.label })
    }

    @Test
    fun `should send the same tile whatever order the quotas arrive in`() {
        // The driver drops a payload identical to the last one, so an unstable order would republish forever.
        val readings = listOf(
            reading(30.0, quotaType = QuotaType.Session),
            reading(30.0, quotaType = QuotaType.Weekly),
            reading(30.0, provider = "codex", name = "Codex"),
            reading(8.0, provider = "gemini", name = "Gemini"),
            reading(72.0, provider = "zai", name = "Z.ai", quotaType = QuotaType.Weekly),
        )

        val first = payload(readings.shuffled())
        val second = payload(readings.shuffled())

        assertEquals(first, second)
        assertEquals(listOf("Gemini 5h", "Claude 5h", "Claude 7d", "Codex 5h", "Z.ai 7d"), first.tile?.metrics?.map { it.label })
    }

    @Test
    fun `should show only the six lowest windows on the tile`() {
        val payload = payload(
            listOf(
                reading(4.0, quotaType = QuotaType.Session),
                reading(12.0, quotaType = QuotaType.Weekly),
                reading(23.0, quotaType = QuotaType.ModelSpecific("opus")),
                reading(31.0, provider = "codex", name = "Codex", quotaType = QuotaType.Session),
                reading(38.0, provider = "codex", name = "Codex", quotaType = QuotaType.Weekly),
                reading(46.0, provider = "codex", name = "Codex", quotaType = QuotaType.ModelSpecific("gpt-5")),
                reading(57.0, provider = "gemini", name = "Gemini", quotaType = QuotaType.Session),
                reading(68.0, provider = "gemini", name = "Gemini", quotaType = QuotaType.Weekly),
                reading(79.0, provider = "gemini", name = "Gemini", quotaType = QuotaType.ModelSpecific("pro")),
            ),
        )

        assertEquals(6, payload.tile?.metrics?.size)
        assertEquals("4", payload.tile?.metrics?.first()?.value)
        assertEquals("46", payload.tile?.metrics?.last()?.value)
    }

    // Labels

    @Test
    fun `should label windows without the provider name when one provider reports them all`() {
        val payload = payload(listOf(reading(70.0, quotaType = QuotaType.Session), reading(80.0, quotaType = QuotaType.Weekly)))

        assertEquals(listOf("5h", "7d"), payload.tile?.metrics?.map { it.label })
    }

    @Test
    fun `should name the provider beside each window when several providers report`() {
        val payload = payload(listOf(reading(70.0, provider = "claude", name = "Claude"), reading(80.0, provider = "codex", name = "Codex")))

        assertEquals(listOf("Claude 5h", "Codex 5h"), payload.tile?.metrics?.map { it.label })
    }

    @Test
    fun `should label a window with its quota's own short title over 7d`() {
        val payload = payload(listOf(reading(70.0, quotaType = QuotaType.Weekly, compactTitle = "Spark 7d")))

        assertEquals("Spark 7d", payload.tile?.metrics?.first()?.label)
    }

    // The bar

    @Test
    fun `should fill the tile's bar from the lowest percentage window`() {
        val payload = payload(listOf(reading(70.0, quotaType = QuotaType.Weekly), reading(45.0, quotaType = QuotaType.Session)))

        assertEquals(45.0, payload.tile?.progress)
    }

    @Test
    fun `should keep the bar from the next percentage window when a dollar balance leads the tile`() {
        val payload = payload(
            listOf(
                reading(5.0, provider = "credits", name = "Credits", quotaType = QuotaType.ModelSpecific("credits"), dollarRemainingNanos = twoTen),
                reading(70.0, provider = "claude", name = "Claude", quotaType = QuotaType.Weekly),
            ),
        )

        // The balance leads; the bar falls through to the window that has a percentage to draw.
        assertEquals(criticalTint, payload.tile?.tintHex)
        assertEquals("$2.10", payload.tile?.metrics?.first()?.value)
        assertEquals(70.0, payload.tile?.progress)
    }

    // Numbers

    @Test
    fun `should show the percentage left, not the percentage used`() {
        val payload = payload(listOf(reading(42.0)))

        assertEquals("42", payload.tile?.metrics?.first()?.value)
        assertEquals("%", payload.tile?.metrics?.first()?.unit)
        assertEquals("42", payload.gauge?.value)
    }

    @Test
    fun `should show a dollar balance with no percent sign and no bar`() {
        val payload = payload(
            listOf(reading(60.0, provider = "credits", name = "Credits", quotaType = QuotaType.ModelSpecific("credits"), dollarRemainingNanos = twoTen)),
        )

        assertEquals("$2.10", payload.tile?.metrics?.first()?.value)
        assertNull(payload.tile?.metrics?.first()?.unit)
        assertEquals("$2.10", payload.gauge?.value)
        assertNull(payload.gauge?.unit)
        assertNull(payload.gauge?.progress)
    }

    // The gauge

    @Test
    fun `should show the window the person pinned on the widget gauge`() {
        val payload = payload(
            listOf(reading(8.0, provider = "claude", name = "Claude"), reading(70.0, provider = "codex", name = "Codex", quotaType = QuotaType.Weekly)),
            gaugeSelection = NotifyGaugeSelection(providerId = "codex", quotaKey = "weekly"),
        )

        assertEquals("70", payload.gauge?.value)
        assertEquals(70.0, payload.gauge?.progress)
        assertEquals(healthyTint, payload.gauge?.tintHex)
        assertEquals(true, payload.gauge?.detail?.contains("Codex 7d"))
    }

    @Test
    fun `should show the worst window on the widget gauge when none is pinned`() {
        val payload = payload(
            listOf(reading(8.0, provider = "claude", name = "Claude"), reading(70.0, provider = "codex", name = "Codex", quotaType = QuotaType.Weekly)),
        )

        assertEquals("8", payload.gauge?.value)
        assertEquals(criticalTint, payload.gauge?.tintHex)
        assertEquals(true, payload.gauge?.detail?.contains("Claude 5h"))
    }

    @Test
    fun `should show the worst window on the widget gauge when the pinned one stops reporting`() {
        val payload = payload(
            listOf(reading(8.0, provider = "claude", name = "Claude"), reading(70.0, provider = "codex", name = "Codex", quotaType = QuotaType.Weekly)),
            gaugeSelection = NotifyGaugeSelection(providerId = "gemini", quotaKey = "session"),
        )

        assertEquals("8", payload.gauge?.value)
        assertEquals(true, payload.gauge?.detail?.contains("Claude 5h"))
    }

    // Surfaces the person turned off

    @Test
    fun `should send no Live Activity tile when the person turns it off`() {
        val payload = payload(listOf(reading(42.0)), includesTile = false)

        assertNull(payload.tile)
        assertEquals("42", payload.gauge?.value)
    }

    @Test
    fun `should send no widget gauge when the person turns it off`() {
        val payload = payload(listOf(reading(42.0)), includesGauge = false)

        assertNull(payload.gauge)
        assertEquals("42", payload.tile?.metrics?.first()?.value)
    }

    @Test
    fun `should send no Home Screen tile when the person turns it off`() {
        val payload = payload(listOf(reading(42.0)), includesScreenTile = false)

        assertNull(payload.screenTile)
        assertEquals("42", payload.tile?.metrics?.first()?.value)
    }

    @Test
    fun `should still send the Home Screen tile when the Live Activity is turned off`() {
        val payload = payload(listOf(reading(42.0)), includesTile = false)

        assertNull(payload.tile)
        assertEquals("42", payload.screenTile?.metrics?.first()?.value)
    }

    @Test
    fun `should send the Home Screen the same tile as the Live Activity`() {
        val payload = payload(
            listOf(reading(8.0, provider = "claude", name = "Claude"), reading(70.0, provider = "codex", name = "Codex", quotaType = QuotaType.Weekly)),
        )

        assertNotNull(payload.screenTile)
        assertEquals(payload.tile, payload.screenTile)
    }

    // The summary line

    @Test
    fun `should summarise the provider, window, percentage left and time until reset`() {
        val payload = payload(listOf(reading(42.0, resetsAtSeconds = now + 2 * 3600 + 30)))

        assertEquals(true, payload.tile?.body?.contains("Claude 5h"))
        assertEquals(true, payload.tile?.body?.contains("42% left"))
        assertEquals(true, payload.tile?.body?.contains("resets in"))
        assertNotNull(payload.tile?.trailing)
    }

    @Test
    fun `should order two accounts with the same name and window the same way every time`() {
        // Display names aren't unique, so without a total order these could come back either way.
        val left = NotifyQuotaReading("omp-work", "Oh My Pi", quota(40.0, "omp-work"))
        val right = NotifyQuotaReading("omp-home", "Oh My Pi", quota(40.0, "omp-home"))

        val oneWay = NotifyPayloadBuilder.ordered(listOf(left, right), nowSeconds = now).map { it.providerId }
        val theOther = NotifyPayloadBuilder.ordered(listOf(right, left), nowSeconds = now).map { it.providerId }

        assertEquals(theOther, oneWay)
        assertEquals(listOf("omp-home", "omp-work"), oneWay)
    }
}
