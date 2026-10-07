package com.tddworks.claudebar.quotas

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

class QuotaStatusTest {
    private val hour = 3_600_000L
    private val now = 1_000_000_000_000L

    @Nested
    inner class `under an absolute policy` {
        @Test
        fun `should warn when less than half is left`() {
            val quota = Quota(Left.Share(45.0), QuotaType.Session, "claude")
            assertEquals(QuotaStatus.WARNING, quota.status(StatusPolicy.Absolute, now))
        }

        @Test
        fun `should be depleted when nothing is left`() {
            val quota = Quota(Left.Share(0.0), QuotaType.Weekly, "codex")
            assertEquals(QuotaStatus.DEPLETED, quota.status(StatusPolicy.Absolute, now))
        }
    }

    @Nested
    inner class `under a pace-aware policy` {
        private val paceAware = StatusPolicy.PaceAware(burnRateThreshold = 1.5)

        @Test
        fun `should turn critical when 60 percent is used halfway through the window`() {
            val quota = Quota(Left.Share(40.0), QuotaType.Session, "claude",
                resetsAtMillis = now + 2 * hour + hour / 2, windowMillis = 5 * hour)
            assertEquals(QuotaStatus.CRITICAL, quota.status(paceAware, now))
        }

        @Test
        fun `should stay healthy when usage is well behind the clock`() {
            val quota = Quota(Left.Share(80.0), QuotaType.Session, "claude",
                resetsAtMillis = now + 2 * hour + hour / 2, windowMillis = 5 * hour)
            assertEquals(QuotaStatus.HEALTHY, quota.status(paceAware, now))
        }

        @Test
        fun `should fall back to absolute when the provider gave no window`() {
            val quota = Quota(Left.Share(45.0), QuotaType.Session, "claude", resetsAtMillis = now + hour)
            assertEquals(QuotaStatus.WARNING, quota.status(paceAware, now))
        }
    }

    @Nested
    inner class `a balance with no ceiling` {
        @Test
        fun `should have no percentage`() {
            val quota = Quota(Left.Balance(Money(1240), ceiling = null), QuotaType.TimeLimit("Credits"), "openrouter")
            assertNull(quota.percentLeft)
        }

        @Test
        fun `should be healthy while money remains`() {
            val quota = Quota(Left.Balance(Money(1240), ceiling = null), QuotaType.TimeLimit("Credits"), "openrouter")
            assertEquals(QuotaStatus.HEALTHY, quota.status)
        }
    }

    @Nested
    inner class `a persisted quota key` {
        @Test
        fun `should read back the quota it was saved from`() {
            listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.ModelSpecific("opus"), QuotaType.TimeLimit("Monthly"))
                .forEach { assertEquals(it, QuotaType.fromQuotaKey(it.quotaKey)) }
        }

        @Test
        fun `should read nothing from a key with an empty name`() {
            assertNull(QuotaType.fromQuotaKey("model:"))
        }
    }

    @Nested
    inner class `the feed` {
        @Test
        fun `should report the worst quota after a refresh`() = runTest {
            val source = object : QuotaSource {
                override suspend fun fetch() = listOf(
                    Quota(Left.Share(90.0), QuotaType.Session, "claude"),
                    Quota(Left.Share(10.0), QuotaType.Weekly, "claude"),
                )
            }
            val feed = QuotaFeed(source, StatusPolicy.Absolute)

            feed.refresh(now)

            assertEquals(QuotaStatus.CRITICAL, feed.overall.value)
        }
    }
}
