package com.tddworks.claudebar.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class NotchActivityResolverTest {
    private val now = 1_700_000_000.0
    private val resolver = NotchActivityResolver(finishedDisplayDurationSeconds = 4.0)

    private fun running(id: String, startedAt: Double? = null) =
        Session(id = id, cwd = "/Users/me/github/$id", startedAtSeconds = startedAt ?: (now - 60))

    private fun quota(percentRemaining: Double, provider: String = "claude") = sessionQuota(percentRemaining, provider)

    // Nothing to say

    @Test
    fun `should show nothing in the notch when no session runs and no quota is known`() {
        assertNull(resolver.resolve(sessions = emptyList(), quotas = emptyList(), headlineQuota = null, nowSeconds = now))
    }

    @Test
    fun `should show nothing in the notch for a healthy quota that is not the headline`() {
        assertNull(resolver.resolve(sessions = emptyList(), quotas = listOf(quota(80.0)), headlineQuota = null, nowSeconds = now))
    }

    @Test
    fun `should show nothing in the notch for a quota only in warning`() {
        // 35% remaining is QuotaStatus.WARNING — visible in the popover, not in the notch.
        assertNull(resolver.resolve(sessions = emptyList(), quotas = listOf(quota(35.0)), headlineQuota = null, nowSeconds = now))
    }

    // Session phases

    @Test
    fun `should show a running session as working`() {
        val result = resolver.resolve(sessions = listOf(running("claudebar")), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.Working(running("claudebar")), result)
    }

    @Test
    fun `should show a session with a running subagent as agents working`() {
        val session = running("claudebar").subagentStarted()

        val result = resolver.resolve(sessions = listOf(session), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals(1, result?.session?.activeSubagentCount)
        assertEquals(NotchActivity.AgentsWorking(session), result)
    }

    @Test
    fun `should show a blocked session as awaiting input, with its pending prompt`() {
        val session = running("claudebar").awaitInput("Bash · rm -rf build/")

        val result = resolver.resolve(sessions = listOf(session), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.AwaitingInput(session), result)
        assertEquals("Bash · rm -rf build/", result?.session?.pendingPrompt)
    }

    // Priority

    @Test
    fun `should show the blocked session over any number of working sessions`() {
        val blocked = running("claudebar", startedAt = now - 10).awaitInput("Write · Package.swift")
        val busy = running("asc").subagentStarted().subagentStarted()

        val result = resolver.resolve(sessions = listOf(busy, running("billfold"), blocked), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals("claudebar", result?.session?.id)
    }

    @Test
    fun `should show a critical quota over a working session`() {
        val result = resolver.resolve(sessions = listOf(running("claudebar")), quotas = listOf(quota(5.0)), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.QuotaThreshold(quota(5.0)), result)
    }

    @Test
    fun `should show a blocked session over a critical quota`() {
        val blocked = running("claudebar").awaitInput("Bash · git push")

        val result = resolver.resolve(sessions = listOf(blocked), quotas = listOf(quota(0.0)), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.AwaitingInput(blocked), result)
    }

    @Test
    fun `should show the lowest quota when several are past the threshold`() {
        val result = resolver.resolve(
            sessions = emptyList(),
            quotas = listOf(quota(18.0, provider = "copilot"), quota(3.0, provider = "claude"), quota(60.0, provider = "codex")),
            headlineQuota = null,
            nowSeconds = now,
        )

        assertEquals(NotchActivity.QuotaThreshold(quota(3.0, provider = "claude")), result)
    }

    @Test
    fun `should show the longest-running blocked session when several are blocked`() {
        val early = running("claudebar", startedAt = now - 600).awaitInput("Bash · make")
        val late = running("asc", startedAt = now - 30).awaitInput("Bash · ls")

        val result = resolver.resolve(sessions = listOf(late, early), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals("claudebar", result?.session?.id)
    }

    // The idle glance

    @Test
    fun `should show the headline quota at a glance when nothing is happening`() {
        // ClaudeBar is a quota monitor. With no session running, how much is left is still
        // the thing the person came for.
        val headline = quota(86.0)

        val result = resolver.resolve(sessions = emptyList(), quotas = listOf(headline), headlineQuota = headline, nowSeconds = now)

        assertEquals(NotchActivity.QuotaGlance(headline), result)
    }

    @Test
    fun `should glance at the chosen headline quota even when another quota is lower`() {
        val headline = quota(86.0, provider = "claude")
        val lower = quota(55.0, provider = "codex")

        val result = resolver.resolve(sessions = emptyList(), quotas = listOf(lower, headline), headlineQuota = headline, nowSeconds = now)

        assertEquals(NotchActivity.QuotaGlance(headline), result)
    }

    @Test
    fun `should show a working session over the headline glance`() {
        val headline = quota(86.0)

        val result = resolver.resolve(sessions = listOf(running("claudebar")), quotas = listOf(headline), headlineQuota = headline, nowSeconds = now)

        assertEquals(NotchActivity.Working(running("claudebar")), result)
    }

    @Test
    fun `should show a quota past the threshold over the headline glance`() {
        val headline = quota(86.0, provider = "claude")
        val critical = quota(4.0, provider = "codex")

        val result = resolver.resolve(sessions = emptyList(), quotas = listOf(headline, critical), headlineQuota = headline, nowSeconds = now)

        assertEquals(NotchActivity.QuotaThreshold(critical), result)
    }

    @Test
    fun `should show no glance before the first quotas arrive`() {
        assertNull(resolver.resolve(sessions = emptyList(), quotas = emptyList(), headlineQuota = null, nowSeconds = now))
    }

    // The finished flash

    @Test
    fun `should show a session that just stopped as finished`() {
        val session = running("claudebar").stop(now - 1)

        val result = resolver.resolve(sessions = listOf(session), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.Finished(session), result)
    }

    @Test
    fun `should show an ended session as finished for four seconds`() {
        val session = running("claudebar").end(now - 3)

        assertEquals(
            NotchActivity.Finished(session),
            resolver.resolve(sessions = listOf(session), quotas = emptyList(), headlineQuota = null, nowSeconds = now),
        )
    }

    @Test
    fun `should stop showing finished once four seconds have passed`() {
        val session = running("claudebar").end(now - 5)

        assertNull(resolver.resolve(sessions = listOf(session), quotas = emptyList(), headlineQuota = null, nowSeconds = now))
    }

    @Test
    fun `should show the next working session once the finished flash has passed`() {
        val done = running("claudebar").end(now - 30)
        val stillGoing = running("asc")

        val result = resolver.resolve(sessions = listOf(done, stillGoing), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals(NotchActivity.Working(stillGoing), result)
    }

    @Test
    fun `should briefly show a just-finished session over one still working`() {
        val done = running("claudebar").end(now - 1)

        val result = resolver.resolve(sessions = listOf(done, running("asc")), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals("claudebar", result?.session?.id)
    }

    @Test
    fun `should show a blocked session over a finished flash`() {
        val done = running("asc").end(now)
        val blocked = running("claudebar").awaitInput("Bash · rm")

        val result = resolver.resolve(sessions = listOf(done, blocked), quotas = emptyList(), headlineQuota = null, nowSeconds = now)

        assertEquals("claudebar", result?.session?.id)
    }
}
