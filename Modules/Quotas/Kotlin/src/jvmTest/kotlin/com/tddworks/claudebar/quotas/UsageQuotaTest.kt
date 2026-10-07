package com.tddworks.claudebar.quotas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

private const val NOW = 1_000_000.0
private const val HOUR = 3600.0

private fun quota(
    percent: Double,
    type: QuotaType = QuotaType.Session,
    resetsIn: Double? = null,
    window: Double? = null,
    dollarRemaining: Long? = null,
    dollarCap: Long? = null,
    currency: String? = null,
) = UsageQuota(
    percent, type, "claude", resetsIn?.let { NOW + it }, null, window,
    dollarRemaining, dollarCap?.let { cap -> dollarRemaining?.let { cap - it } }, dollarCap,
    null, null, null, currency,
)

class UsageQuotaTest {

    @Nested
    inner class `how much is left` {
        @Test
        fun `should never show more than 100 percent left`() {
            assertEquals(100.0, quota(120.0).percentRemaining)
        }

        @Test
        fun `should keep a negative share when over quota`() {
            assertEquals(-5.0, quota(-5.0).percentRemaining)
        }

        @Test
        fun `should read a balance written as 100 percent as money with no percentage`() {
            val balance = quota(100.0, dollarRemaining = 12_400_000)
            assertEquals(Left.Balance(Money(12_400_000), null), balance.left)
            assertNull(balance.percentLeftOrNull)
            assertTrue(balance.isBalance)
        }

        @Test
        fun `should give a capped spend meter its share of the cap`() {
            val meter = UsageQuota(
                Left.Balance(Money(12_400_000), Money(50_000_000)), QuotaType.Weekly, "openrouter",
                null, null, null, null, null, null,
            )
            assertEquals(24.8, meter.percentRemaining)
            assertEquals(37_600_000L, meter.dollarUsedMicros)
        }

        @Test
        fun `should give no share when the cap is in another currency`() {
            val meter = UsageQuota(
                Left.Balance(Money(10_000_000, "USD"), Money(50_000_000, "CNY")), QuotaType.Weekly, "x",
                null, null, null, null, null, null,
            )
            assertEquals(100.0, meter.percentRemaining)
        }
    }

    @Nested
    inner class `its status` {
        @Test
        fun `should warn when less than half is left`() {
            assertEquals(QuotaStatus.WARNING, quota(45.0).status)
        }

        @Test
        fun `should be critical under 20 percent`() {
            assertEquals(QuotaStatus.CRITICAL, quota(19.9).status)
        }

        @Test
        fun `should be depleted when nothing is left`() {
            assertEquals(QuotaStatus.DEPLETED, quota(0.0).status)
        }

        @Test
        fun `should keep a balance healthy while money remains`() {
            assertEquals(QuotaStatus.HEALTHY, quota(100.0, dollarRemaining = 1).status)
        }

        @Test
        fun `should deplete a balance at zero`() {
            assertEquals(QuotaStatus.DEPLETED, quota(100.0, dollarRemaining = 0).status)
        }

        @Test
        fun `should stay healthy under a pace-aware policy when usage trails the clock`() {
            val q = quota(45.0, resetsIn = 0.5 * HOUR, window = 5 * HOUR)
            assertEquals(QuotaStatus.HEALTHY, q.status(StatusPolicy.PaceAware(1.5), NOW))
        }

        @Test
        fun `should turn critical under a pace-aware policy when usage runs ahead of the clock`() {
            val q = quota(40.0, resetsIn = 2.5 * HOUR, window = 5 * HOUR)
            assertEquals(QuotaStatus.CRITICAL, q.status(StatusPolicy.PaceAware(1.5), NOW))
        }

        @Test
        fun `should fall back to absolute thresholds when the window is unknown`() {
            val q = quota(45.0, resetsIn = HOUR)
            assertEquals(QuotaStatus.WARNING, q.status(StatusPolicy.PaceAware(1.5), NOW))
        }

        @Test
        fun `should read the settings as a pace-aware policy only when the warning is on`() {
            assertEquals(StatusPolicy.Absolute, StatusPolicy.from(false, 1.5))
            assertEquals(StatusPolicy.PaceAware(1.5), StatusPolicy.from(true, 1.5))
        }
    }

    @Nested
    inner class `its pace` {
        @Test
        fun `should know half the window has passed`() {
            assertEquals(50.0, quota(50.0, resetsIn = 2.5 * HOUR, window = 5 * HOUR).percentTimeElapsed(NOW))
        }

        @Test
        fun `should not guess a window from the quota's name`() {
            assertNull(quota(50.0, resetsIn = HOUR).percentTimeElapsed(NOW))
        }

        @Test
        fun `should have no pace for a balance`() {
            assertEquals(UsagePace.UNKNOWN, quota(100.0, resetsIn = HOUR, window = 5 * HOUR, dollarRemaining = 5).pace(NOW))
        }

        @Test
        fun `should run hot when usage is well ahead of the clock`() {
            val q = quota(40.0, resetsIn = 2.5 * HOUR, window = 5 * HOUR)
            assertEquals(UsagePace.AHEAD, q.pace(NOW))
            assertEquals("10% above expected usage", q.paceInsight(NOW))
        }

        @Test
        fun `should be on track within five points of the clock`() {
            assertEquals(UsagePace.ON_PACE, quota(52.0, resetsIn = 2.5 * HOUR, window = 5 * HOUR).pace(NOW))
        }

        @Test
        fun `should grade the pace tick as runaway past 120 percent projected`() {
            assertEquals(PaceLevel.RUNAWAY, quota(30.0, resetsIn = 2.5 * HOUR, window = 5 * HOUR).paceLevel(NOW))
        }

        @Test
        fun `should not grade the pace tick in the first moments of a window`() {
            assertNull(PaceLevel.from(percentUsed = 1.0, percentTimeElapsed = 2.0))
        }
    }

    @Nested
    inner class `when it resets` {
        @Test
        fun `should show hours and minutes compactly`() {
            assertEquals("3:58", quota(50.0, resetsIn = 3 * HOUR + 58 * 60 + 30).compactResetTime(NOW))
        }

        @Test
        fun `should show days compactly past a day`() {
            assertEquals("2d", quota(50.0, resetsIn = 50 * HOUR).compactResetTime(NOW))
        }

        @Test
        fun `should say soon under a minute`() {
            assertEquals("soon", quota(50.0, resetsIn = 30.0).compactResetTime(NOW))
        }

        @Test
        fun `should spell out every part of the countdown`() {
            assertEquals("Resets in 2d 5h 30m", quota(50.0, resetsIn = 53.5 * HOUR).resetTimestampDescription(NOW))
        }

        @Test
        fun `should never count down below zero once the reset has passed`() {
            assertEquals("Resets soon", quota(50.0, resetsIn = -HOUR).resetDescription(NOW))
        }
    }

    @Test
    fun `should show the symbol for a known currency and the code for an unknown one`() {
        assertEquals("¥", UsageQuota.currencySymbol("cny"))
        assertEquals("CHF ", UsageQuota.currencySymbol("chf"))
    }

    @Test
    fun `should need attention only when not healthy`() {
        assertFalse(quota(80.0).needsAttention)
        assertTrue(quota(30.0).needsAttention)
    }
}
