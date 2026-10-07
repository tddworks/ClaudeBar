package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.quotas.QuotaStatus
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ProviderBadgeStateTest {
    /** A login as the badge sees it — one waiting for setup also carries the error that says so. */
    private fun login(needsSetup: Boolean = false, readsUsage: Boolean = false, failed: Boolean = false, syncing: Boolean = false) =
        ProviderBadgeState.Login(isSyncing = syncing, failed = needsSetup || failed, needsSetup = needsSetup, readsUsage = readsUsage)

    @Test
    fun `should show the provider unavailable, not healthy, when it failed before any usage was read`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = null, hasError = true)

        assertEquals(ProviderBadgeState.Unavailable, state)
        assertFalse(state.hasData)
    }

    @Test
    fun `should show the provider awaiting data, not healthy, before any usage or failure arrives`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = null, hasError = false)

        assertEquals(ProviderBadgeState.AwaitingData, state)
        assertFalse(state.hasData)
    }

    @Test
    fun `should show the provider not set up, not unavailable, when it waits to be set up`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = null, hasError = true, needsSetup = true)

        assertEquals(ProviderBadgeState.NotSetUp, state)
        assertFalse(state.hasData)
    }

    @Test
    fun `should say nothing alarming when the provider waits for setup but its usage is read (#198)`() {
        // A Claude Desktop user: no Claude Code, so no limits — but Desktop's tokens today are read.
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = null, hasError = true, needsSetup = true, readsUsage = true)

        assertEquals(ProviderBadgeState.UsageOnly, state)
        assertFalse(state.hasData)
    }

    @Test
    fun `should keep showing the last quota status when a later setup check failed`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = QuotaStatus.HEALTHY, hasError = true, needsSetup = true)

        assertEquals(ProviderBadgeState.Quota(QuotaStatus.HEALTHY), state)
    }

    @Test
    fun `should show the quota status of the usage it read`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = QuotaStatus.WARNING, hasError = false)

        assertEquals(ProviderBadgeState.Quota(QuotaStatus.WARNING), state)
        assertTrue(state.hasData)
    }

    @Test
    fun `should keep showing the last quota status when a later refresh failed`() {
        val state = ProviderBadgeState.from(isSyncing = false, quotaStatus = QuotaStatus.CRITICAL, hasError = true)

        assertEquals(ProviderBadgeState.Quota(QuotaStatus.CRITICAL), state)
    }

    @Test
    fun `should show syncing whatever else the provider's state is`() {
        assertEquals(ProviderBadgeState.Syncing, ProviderBadgeState.from(isSyncing = true, quotaStatus = null, hasError = true))
        assertEquals(ProviderBadgeState.Syncing, ProviderBadgeState.from(isSyncing = true, quotaStatus = QuotaStatus.HEALTHY, hasError = false))
    }

    // A tab of logins

    @Test
    fun `should show the tab not set up when every login waits for setup`() {
        val state = ProviderBadgeState.of(listOf(login(needsSetup = true), login(needsSetup = true)), quotaStatus = null)

        assertEquals(ProviderBadgeState.NotSetUp, state)
    }

    @Test
    fun `should show no alarming badge on the tab when a login waiting for setup has its usage read`() {
        val state = ProviderBadgeState.of(listOf(login(needsSetup = true, readsUsage = true)), quotaStatus = null)

        assertEquals(ProviderBadgeState.UsageOnly, state)
        assertFalse(state.showsBadge)
    }

    @Test
    fun `should show the tab unavailable, not waiting for setup, when one login really failed`() {
        val state = ProviderBadgeState.of(listOf(login(needsSetup = true), login(failed = true)), quotaStatus = null)

        assertEquals(ProviderBadgeState.Unavailable, state)
        assertTrue(state.showsBadge)
    }

    @Test
    fun `should show the tab awaiting data when it has no logins`() {
        assertEquals(ProviderBadgeState.AwaitingData, ProviderBadgeState.of(emptyList(), quotaStatus = null))
    }

    @Test
    fun `should show the tab syncing when one of its logins is syncing`() {
        assertEquals(ProviderBadgeState.Syncing, ProviderBadgeState.of(listOf(login(syncing = true), login(failed = true)), quotaStatus = null))
    }
}
