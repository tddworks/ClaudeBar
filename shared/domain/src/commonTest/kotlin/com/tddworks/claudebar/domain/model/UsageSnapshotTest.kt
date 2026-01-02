package com.tddworks.claudebar.domain.model

import kotlinx.datetime.Clock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class UsageSnapshotTest {

    @Test
    fun `overall status returns worst status among quotas`() {
        val snapshot = UsageSnapshot(
            providerId = "test",
            quotas = listOf(
                UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Session, providerId = "test"),
                UsageQuota(percentRemaining = 0.0, quotaType = QuotaType.Weekly, providerId = "test"),
                UsageQuota(percentRemaining = 50.0, quotaType = QuotaType.ModelSpecific("opus"), providerId = "test")
            ),
            capturedAt = Clock.System.now()
        )

        assertEquals(QuotaStatus.DEPLETED, snapshot.overallStatus)
    }

    @Test
    fun `overall status is HEALTHY when no quotas`() {
        val snapshot = UsageSnapshot.empty("test")

        assertEquals(QuotaStatus.HEALTHY, snapshot.overallStatus)
    }

    @Test
    fun `lowest quota returns quota with smallest percent remaining`() {
        val snapshot = UsageSnapshot(
            providerId = "test",
            quotas = listOf(
                UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Session, providerId = "test"),
                UsageQuota(percentRemaining = 15.0, quotaType = QuotaType.Weekly, providerId = "test"),
                UsageQuota(percentRemaining = 50.0, quotaType = QuotaType.ModelSpecific("opus"), providerId = "test")
            ),
            capturedAt = Clock.System.now()
        )

        assertEquals(15.0, snapshot.lowestQuota?.percentRemaining)
    }

    @Test
    fun `session quota returns correct quota type`() {
        val sessionQuota = UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Session, providerId = "test")
        val snapshot = UsageSnapshot(
            providerId = "test",
            quotas = listOf(sessionQuota),
            capturedAt = Clock.System.now()
        )

        assertEquals(sessionQuota, snapshot.sessionQuota)
    }

    @Test
    fun `weekly quota returns null when not present`() {
        val snapshot = UsageSnapshot(
            providerId = "test",
            quotas = listOf(
                UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Session, providerId = "test")
            ),
            capturedAt = Clock.System.now()
        )

        assertNull(snapshot.weeklyQuota)
    }

    @Test
    fun `model specific quotas filters correctly`() {
        val snapshot = UsageSnapshot(
            providerId = "test",
            quotas = listOf(
                UsageQuota(percentRemaining = 80.0, quotaType = QuotaType.Session, providerId = "test"),
                UsageQuota(percentRemaining = 50.0, quotaType = QuotaType.ModelSpecific("opus"), providerId = "test"),
                UsageQuota(percentRemaining = 60.0, quotaType = QuotaType.ModelSpecific("sonnet"), providerId = "test")
            ),
            capturedAt = Clock.System.now()
        )

        assertEquals(2, snapshot.modelSpecificQuotas.size)
    }
}
