package com.tddworks.claudebar.quotas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

private const val CAPTURED = 5_000.0

private fun q(percent: Double, type: QuotaType = QuotaType.Session, group: String? = null, balance: Long? = null) =
    UsageQuota(percent, type, "claude", null, null, null, balance, null, null, group, null, null, null)

private fun snapshot(vararg quotas: UsageQuota, metrics: List<ExtensionMetric>? = null) =
    UsageSnapshot("claude", quotas.toList(), CAPTURED, null, null, null, null, null, null, metrics)

private fun metric(value: String, group: String?) = ExtensionMetric("Account", value, "", null, null, null, null, group)

class UsageSnapshotTest {

    @Nested
    inner class `its overall status` {
        @Test
        fun `should be the worst quota's status`() {
            assertEquals(QuotaStatus.CRITICAL, snapshot(q(90.0), q(10.0, QuotaType.Weekly)).overallStatus)
        }

        @Test
        fun `should be healthy with no quotas`() {
            assertEquals(QuotaStatus.HEALTHY, snapshot().overallStatus)
        }
    }

    @Nested
    inner class `its lowest quota` {
        @Test
        fun `should be the one with the least left`() {
            assertEquals(30.0, snapshot(q(80.0), q(30.0, QuotaType.Weekly)).lowestQuota?.percentRemaining)
        }

        @Test
        fun `should not be a balance while a share is there to compare`() {
            val share = q(60.0, QuotaType.Weekly)
            assertEquals(share, snapshot(q(100.0, balance = 1), share).lowestQuota)
        }
    }

    @Nested
    inner class `hiding quotas` {
        @Test
        fun `should leave out the quotas a person hid`() {
            val visible = snapshot(q(80.0), q(10.0, QuotaType.Weekly)).hiding(setOf("weekly"))
            assertEquals(listOf("session"), visible.quotas.map { it.quotaType.quotaKey })
        }

        @Test
        fun `should hide none when every quota is hidden`() {
            val usage = snapshot(q(80.0), q(10.0, QuotaType.Weekly))
            assertSame(usage, usage.hiding(setOf("session", "weekly")))
        }
    }

    @Nested
    inner class `its groups` {
        @Test
        fun `should keep groups in order of first appearance with ungrouped ones first`() {
            val groups = snapshot(q(1.0), q(2.0, group = "work"), q(3.0, group = "home"), q(4.0, group = "work")).quotaGroups
            assertEquals(listOf(null, "work", "home"), groups.map { it.title })
            assertEquals(2, groups[1].quotas.size)
        }

        @Test
        fun `should make a note-only section for an account with no quotas`() {
            val groups = snapshot(q(1.0, group = "work"), metrics = listOf(metric("No usage reported", "spare"))).quotaGroups
            assertEquals("No usage reported", groups.last().note)
            assertTrue(groups.last().noteIsHeader)
        }

        @Test
        fun `should join several notes for one group line by line`() {
            val groups = snapshot(metrics = listOf(metric("a", "x"), metric("b", "x"))).quotaGroups
            assertEquals("a\nb", groups.single().note)
        }

        @Test
        fun `should know there are groups when only a metric is tagged`() {
            assertTrue(snapshot(q(1.0), metrics = listOf(metric("n", "x"))).hasQuotaGroups)
            assertFalse(snapshot(q(1.0)).hasQuotaGroups)
        }
    }

    @Test
    fun `should find a quota by the key it was saved under`() {
        val opus = q(50.0, QuotaType.ModelSpecific("opus"))
        assertEquals(opus, snapshot(q(80.0), opus).quotaForKey("model:opus"))
        assertNull(snapshot(q(80.0)).quotaForKey("nonsense"))
    }

    @Test
    fun `should describe its age in the largest whole unit`() {
        val usage = snapshot()
        assertEquals("Just now", usage.ageDescription(CAPTURED + 59))
        assertEquals("4m ago", usage.ageDescription(CAPTURED + 4 * 60 + 5))
        assertEquals("2h ago", usage.ageDescription(CAPTURED + 2 * 3600 + 1))
        assertTrue(usage.isStale(CAPTURED + 301))
    }
}

class CostTest {
    private val dollar = 1_000_000_000L

    private fun cost(total: Long, budget: Long? = null) = CostUsage(
        total, budget, 0.0, 0.0, 0, 0, "claude", CostUsage.Kind.EXTRA_USAGE, 0.0, null, null, emptyList(),
    )

    @Test
    fun `should be on track under 80 percent of the budget`() {
        assertEquals(BudgetStatus.WITHIN_BUDGET, BudgetStatus.from(15 * dollar + dollar * 99 / 100, 20 * dollar))
    }

    @Test
    fun `should be near the limit from 80 percent`() {
        assertEquals(BudgetStatus.APPROACHING_LIMIT, BudgetStatus.from(16 * dollar, 20 * dollar))
    }

    @Test
    fun `should be over budget once the budget is spent`() {
        assertEquals(BudgetStatus.OVER_BUDGET, BudgetStatus.from(20 * dollar, 20 * dollar))
    }

    @Test
    fun `should never be over a budget of nothing`() {
        assertEquals(BudgetStatus.WITHIN_BUDGET, BudgetStatus.from(5 * dollar, 0))
    }

    @Test
    fun `should never show less than nothing left of the budget`() {
        assertEquals(0L, cost(25 * dollar, 20 * dollar).budgetRemainingNanos)
        assertEquals(5 * dollar, cost(15 * dollar, 20 * dollar).budgetRemainingNanos)
    }

    @Test
    fun `should judge only a built-in budget it has`() {
        assertNull(cost(5 * dollar).budgetStatusFromBuiltIn)
        assertEquals(75.0, cost(15 * dollar, 20 * dollar).budgetPercentUsed(20 * dollar))
    }

    @Test
    fun `should offer guest passes only on Claude Max`() {
        assertTrue(AccountTier.ClaudeMax.supportsGuestPasses)
        assertFalse(AccountTier.Custom("MAX").supportsGuestPasses)
    }
}

class DailyUsageTest {
    private val dollar = 1_000_000_000L

    private fun day(cost: Long = 0, tokens: Long = 0, time: Double = 0.0, input: Long = 0, cacheRead: Long = 0) =
        DailyUsageStat(0.0, cost, tokens, time, 1, input, 0, 0, cacheRead, 0)

    @Test
    fun `should compare today's cost with the previous day's`() {
        val report = DailyUsageReport(day(cost = 15 * dollar), day(cost = 20 * dollar))
        assertEquals(-5 * dollar, report.costDeltaNanos)
        assertEquals(-25.0, report.costChangePercent)
    }

    @Test
    fun `should have no cost change when the previous day cost nothing`() {
        assertNull(DailyUsageReport(day(cost = dollar), day()).costChangePercent)
    }

    @Test
    fun `should give today's share of the two days`() {
        assertEquals(0.25, DailyUsageReport(day(tokens = 100), day(tokens = 300)).tokenProgress)
        assertEquals(0.0, DailyUsageReport(day(), day()).timeProgress)
    }

    @Test
    fun `should count the cache hit rate against input that missed it`() {
        assertEquals(0.9, day(input = 10, cacheRead = 90).cacheHitRate)
        assertEquals(0.0, day().cacheHitRate)
    }

    @Test
    fun `should be empty with no tokens, cost or time`() {
        assertTrue(DailyUsageStat.empty(0.0).isEmpty)
        assertFalse(day(time = 1.0).isEmpty)
    }
}
