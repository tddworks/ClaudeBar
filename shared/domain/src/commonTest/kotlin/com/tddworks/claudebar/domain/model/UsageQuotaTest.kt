package com.tddworks.claudebar.domain.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class UsageQuotaTest {

    @Test
    fun `quota status is HEALTHY when percent remaining is above 25`() {
        val quota = UsageQuota(
            percentRemaining = 50.0,
            quotaType = QuotaType.Session,
            providerId = "test"
        )

        assertEquals(QuotaStatus.HEALTHY, quota.status)
    }

    @Test
    fun `quota status is WARNING when percent remaining is between 20 and 50`() {
        val quota = UsageQuota(
            percentRemaining = 35.0,
            quotaType = QuotaType.Session,
            providerId = "test"
        )

        assertEquals(QuotaStatus.WARNING, quota.status)
    }

    @Test
    fun `quota status is CRITICAL when percent remaining is below 20`() {
        val quota = UsageQuota(
            percentRemaining = 15.0,
            quotaType = QuotaType.Session,
            providerId = "test"
        )

        assertEquals(QuotaStatus.CRITICAL, quota.status)
    }

    @Test
    fun `quota status is DEPLETED when percent remaining is zero`() {
        val quota = UsageQuota(
            percentRemaining = 0.0,
            quotaType = QuotaType.Session,
            providerId = "test"
        )

        assertEquals(QuotaStatus.DEPLETED, quota.status)
    }

    @Test
    fun `quotas are comparable by percentRemaining`() {
        val low = UsageQuota(percentRemaining = 10.0, quotaType = QuotaType.Session, providerId = "test")
        val high = UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Weekly, providerId = "test")

        assertTrue(low < high)
    }
}
