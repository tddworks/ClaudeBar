package com.tddworks.claudebar.activity

import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageQuota
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** A session quota of [percentRemaining] for [provider], as the notch tests use. */
internal fun sessionQuota(percentRemaining: Double, provider: String = "claude") = UsageQuota(
    percentRemaining, QuotaType.Session, provider,
    null, null, null, null, null, null, null, null, null, null,
)

class NotchActivityTest {
    private fun session(id: String = "s1") = Session(id = id, cwd = "/Users/me/github/claudebar", startedAtSeconds = 1_700_000_000.0)

    private fun quota(percentRemaining: Double) = sessionQuota(percentRemaining)

    @Test
    fun `should rank a session awaiting input above every other notch activity`() {
        val blocked = NotchActivity.AwaitingInput(session())

        assertTrue(blocked > NotchActivity.Finished(session()))
        assertTrue(blocked > NotchActivity.QuotaThreshold(quota(2.0)))
        assertTrue(blocked > NotchActivity.AgentsWorking(session()))
        assertTrue(blocked > NotchActivity.Working(session()))
    }

    @Test
    fun `should rank a finished session above quotas and work but below a blocked session`() {
        val finished = NotchActivity.Finished(session())

        assertTrue(finished > NotchActivity.QuotaThreshold(quota(2.0)))
        assertTrue(finished > NotchActivity.AgentsWorking(session()))
        assertTrue(finished < NotchActivity.AwaitingInput(session()))
    }

    @Test
    fun `should rank a quota past the threshold above working sessions`() {
        val quotaActivity = NotchActivity.QuotaThreshold(quota(2.0))

        assertTrue(quotaActivity > NotchActivity.AgentsWorking(session()))
        assertTrue(quotaActivity > NotchActivity.Working(session()))
    }

    @Test
    fun `should rank a session with agents working above a plain working one`() {
        assertTrue(NotchActivity.AgentsWorking(session()) > NotchActivity.Working(session()))
    }

    @Test
    fun `should rank the headline glance below every other notch activity`() {
        val glance = NotchActivity.QuotaGlance(quota(86.0))

        assertTrue(glance < NotchActivity.Working(session()))
        assertTrue(glance < NotchActivity.AgentsWorking(session()))
        assertTrue(glance < NotchActivity.QuotaThreshold(quota(2.0)))
        assertTrue(glance < NotchActivity.Finished(session()))
        assertTrue(glance < NotchActivity.AwaitingInput(session()))
    }

    @Test
    fun `should name the session behind a session activity and none behind a quota`() {
        assertEquals("a", NotchActivity.Working(session("a")).session.id)
        assertEquals("b", NotchActivity.AgentsWorking(session("b")).session.id)
        assertEquals("c", NotchActivity.AwaitingInput(session("c")).session.id)
        assertEquals("d", NotchActivity.Finished(session("d")).session.id)
        assertNull((NotchActivity.QuotaThreshold(quota(2.0)) as NotchActivity).session)
        assertNull((NotchActivity.QuotaGlance(quota(86.0)) as NotchActivity).session)
    }
}
