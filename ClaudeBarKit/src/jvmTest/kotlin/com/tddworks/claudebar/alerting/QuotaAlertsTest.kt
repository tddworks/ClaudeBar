package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/** *Quota alerts* (#68): the person's own percentages, told once when a login falls below one, and again only after it climbs back a point. */
class QuotaAlertsTest {
    private class Told : QuotaAlertAnnouncer {
        val alerts = mutableListOf<QuotaAlert>()
        override suspend fun announce(alert: QuotaAlert) {
            alerts += alert
        }
    }

    private class Kept(var percents: List<Int> = emptyList()) : QuotaAlertSettingsRepository {
        override fun quotaAlertPercents() = percents
        override fun setQuotaAlertPercents(percents: List<Int>) {
            this.percents = percents
        }
    }

    private val told = Told()

    private fun alerts(percents: List<Int>, kept: Kept? = null) = QuotaAlerts(kept ?: Kept(percents), told)

    private fun usage(vararg lefts: Left) = UsageSnapshot(
        providerId = "claude",
        quotas = lefts.map { UsageQuota(it, QuotaType.Session, "claude", null, null, null, null, null, null) },
        capturedAtSeconds = 0.0, accountEmail = null, accountOrganization = null, loginMethod = null,
        accountTier = null, costUsage = null, dailyUsageReport = null, extensionMetrics = null,
    )

    private fun left(percent: Double) = usage(Left.Share(percent))

    private fun dollars(amount: Long) = Money(amount * 1_000_000_000)

    // Telling

    @Test
    fun `should tell once when a login falls below a percentage`() = runBlocking {
        val alerts = alerts(listOf(35))

        alerts.review("claude.work", "Claude · work", left(40.0))
        alerts.review("claude.work", "Claude · work", left(34.0))

        assertEquals(listOf(QuotaAlert(login = "Claude · work", below = 35, left = 34)), told.alerts)
    }

    @Test
    fun `should stay quiet while the login stays below`() = runBlocking {
        val alerts = alerts(listOf(35))

        for (percent in listOf(34.0, 30.0, 31.0, 12.0)) alerts.review("claude", "Claude", left(percent))

        assertEquals(1, told.alerts.size)
    }

    @Test
    fun `should tell again after the login climbs back a point above`() = runBlocking {
        val alerts = alerts(listOf(35))

        for (percent in listOf(34.0, 36.0, 33.0)) alerts.review("claude", "Claude", left(percent))

        assertEquals(listOf(34, 33), told.alerts.map { it.left })
    }

    @Test
    fun `should not tell again when the login climbs back less than a point`() = runBlocking {
        val alerts = alerts(listOf(35))

        for (percent in listOf(34.0, 35.5, 34.0)) alerts.review("claude", "Claude", left(percent))

        assertEquals(1, told.alerts.size)
    }

    @Test
    fun `should tell each percentage a login falls below, highest first`() = runBlocking {
        val alerts = alerts(listOf(35, 60))

        alerts.review("claude", "Claude", left(30.0))

        assertEquals(listOf(60, 35), told.alerts.map { it.below })
    }

    @Test
    fun `should keep each login's crossing its own`() = runBlocking {
        val alerts = alerts(listOf(35))

        alerts.review("claude", "Claude · me", left(30.0))
        alerts.review("claude.work", "Claude · work", left(30.0))

        assertEquals(listOf("Claude · me", "Claude · work"), told.alerts.map { it.login })
    }

    // What it judges

    @Test
    fun `should judge the lowest quota the login shows`() = runBlocking {
        val alerts = alerts(listOf(35))

        alerts.review("claude", "Claude", usage(Left.Share(80.0), Left.Share(20.0)))

        assertEquals(listOf(QuotaAlert(login = "Claude", below = 35, left = 20)), told.alerts)
    }

    @Test
    fun `should judge money with a ceiling by its share`() = runBlocking {
        val alerts = alerts(listOf(35))

        alerts.review("acme", "Acme", usage(Left.Balance(dollars(10), dollars(50))))

        assertEquals(listOf(QuotaAlert(login = "Acme", below = 35, left = 20)), told.alerts)
    }

    @Test
    fun `should never judge a balance without a ceiling`() = runBlocking {
        val alerts = alerts(listOf(35))

        alerts.review("acme", "Acme", usage(Left.Balance(dollars(1), null)))
        alerts.review("acme", "Acme", null)

        assertTrue(told.alerts.isEmpty())
    }

    // The person's percentages

    @Test
    fun `should keep the person's percentages highest first and save them`() {
        val kept = Kept()
        val alerts = alerts(emptyList(), kept)

        assertNull(alerts.add("35"))
        assertNull(alerts.add("60%"))

        assertEquals(listOf(60, 35), alerts.percents)
        assertEquals(listOf(60, 35), kept.percents)
    }

    @Test
    fun `should read the saved percentages at launch`() {
        assertEquals(listOf(60, 35), alerts(listOf(35, 60)).percents)
    }

    @Test
    fun `should forget a percentage the person removes`() {
        val kept = Kept(listOf(35, 60))
        val alerts = alerts(emptyList(), kept)

        alerts.remove(35)

        assertEquals(listOf(60), alerts.percents)
        assertEquals(listOf(60), kept.percents)
    }

    @Test
    fun `should refuse 20 and 0 percent because ClaudeBar already alerts there`() {
        val alerts = alerts(emptyList())

        assertEquals(QuotaAlerts.Refusal.AlreadyAlerted(20), alerts.add("20"))
        assertEquals(QuotaAlerts.Refusal.AlreadyAlerted(0), alerts.add("0"))
        assertTrue(alerts.percents.isEmpty())
    }

    @ParameterizedTest
    @ValueSource(strings = ["100", "-5", "35.5", "lots", ""])
    fun `should refuse anything but a whole percent from 1 to 99`(entry: String) {
        assertEquals(QuotaAlerts.Refusal.NotAPercent, alerts(emptyList()).add(entry))
    }

    @Test
    fun `should refuse a percentage already on the list`() {
        assertEquals(QuotaAlerts.Refusal.AlreadyListed(35), alerts(listOf(35)).add("35"))
    }

    @Test
    fun `should refuse a sixth percentage`() {
        assertEquals(QuotaAlerts.Refusal.Full, alerts(listOf(10, 30, 40, 50, 60)).add("70"))
    }
}
