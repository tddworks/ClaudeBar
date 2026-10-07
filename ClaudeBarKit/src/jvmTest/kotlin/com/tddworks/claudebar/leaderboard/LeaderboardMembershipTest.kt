package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.link
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.stat
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.username
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LeaderboardMembershipTest {
    private val api = FakeLeaderboardAPI()
    private val keys = InMemorySigningKeyStore()
    private val settings = InMemoryLeaderboardSettings()
    private val logs = FakeTokenLogs(setOf("claude", "codex", "mistral"))

    private fun membership() = LeaderboardMembership(api, keys, settings, logs, LeaderboardFixtures.calendar, JvmRandomBytes)

    private suspend fun joined(sharing: Set<String> = setOf("claude")) =
        membership().also { it.join(username("tokenwhale"), sharing) }

    // — Joining —

    @Test
    fun `should keep the person's name, what they share and a key for this Mac when they join`() = runTest {
        val membership = joined(setOf("claude", "codex"))

        assertTrue(membership.isJoined)
        assertEquals("tokenwhale", membership.username?.value)
        assertEquals(setOf("claude", "codex"), membership.sharing)
        assertTrue(membership.isVisible)
        assertEquals(43, SigningKey.of(requireNotNull(keys.stored))?.publicKey?.length)
        assertEquals(LeaderboardRecord("tokenwhale", listOf("claude", "codex"), visible = true, lastUploadSeconds = null), settings.record)
        assertFalse(membership.sharesCountry)
    }

    @Test
    fun `should leave the person outside, with no key kept, when their name is taken`() = runTest {
        api.joinFails = LeaderboardError.UsernameTaken
        val membership = membership()

        val error = thrown { membership.join(username("TokenWhale"), setOf("claude")) }

        assertEquals(LeaderboardError.UsernameTaken, error)
        assertFalse(membership.isJoined)
        assertNull(keys.stored)
        assertNull(settings.record)
    }

    @Test
    fun `should refuse to join sharing a provider that keeps no token logs`() = runTest {
        val membership = membership()

        val error = thrown { membership.join(username("tokenwhale"), setOf("claude", "gemini")) }

        assertEquals(LeaderboardError.NotShareable("gemini"), error)
        assertFalse(membership.isJoined)
    }

    @Test
    fun `should refuse to join sharing no provider`() = runTest {
        val error = thrown { membership().join(username("tokenwhale"), emptySet()) }

        assertEquals(LeaderboardError.NothingShared, error)
    }

    @Test
    fun `should keep the person joined, with their name and what they share, after a relaunch`() = runTest {
        joined(setOf("codex"))

        val restored = membership()

        assertTrue(restored.isJoined)
        assertEquals("tokenwhale", restored.username?.value)
        assertEquals(setOf("codex"), restored.sharing)
    }

    @Test
    fun `should not count the person as joined when this Mac's key is gone`() = runTest {
        joined()
        keys.stored = null

        assertFalse(membership().isJoined)
    }

    // — Sharing —

    @Test
    fun `should remember which providers the person shares after they change them`() = runTest {
        val membership = joined()

        membership.share("mistral")
        membership.stopSharing("claude")

        assertEquals(setOf("mistral"), membership.sharing)
        assertEquals(listOf("mistral"), settings.record?.sharing)
    }

    @Test
    fun `should refuse to share a provider that keeps no token logs after joining`() = runTest {
        val membership = joined()

        val error = thrown { membership.share("gemini") }

        assertEquals(LeaderboardError.NotShareable("gemini"), error)
        assertEquals(setOf("claude"), membership.sharing)
    }

    @Test
    fun `should send only shared providers' days, each one's logins added up`() = runTest {
        val membership = joined(setOf("claude"))

        val days = membership.dailyTokens(
            listOf(
                LoginDays("claude", listOf(stat(day = 4, input = 100, output = 10))),
                LoginDays("claude", listOf(stat(day = 4, input = 1, output = 1, cacheRead = 5))),
                LoginDays("codex", listOf(stat(day = 4, input = 999))),
            ),
        )

        assertEquals(listOf(DailyTokens("claude", "2026-10-04", input = 101, output = 11, cacheWrite = 0, cacheRead = 5, unsplit = 0)), days)
    }

    @Test
    fun `should not send days with no tokens`() = runTest {
        val membership = joined()

        val days = membership.dailyTokens(listOf(LoginDays("claude", listOf(stat(day = 3), stat(day = 4, input = 5)))))

        assertEquals(listOf("2026-10-04"), days.map { it.day })
    }

    @Test
    fun `should send nothing when the person hasn't joined`() {
        val days = membership().dailyTokens(listOf(LoginDays("claude", listOf(stat(day = 4, input = 5)))))

        assertTrue(days.isEmpty())
    }

    // — Visibility and name —

    @Test
    fun `should hide the person from the leaderboard once the server agrees`() = runTest {
        val membership = joined()

        membership.setVisible(false)

        assertFalse(membership.isVisible)
        assertEquals(false, settings.record?.visible)
    }

    @Test
    fun `should keep the person visible when the server can't be reached to hide them`() = runTest {
        val membership = joined()
        api.updateFails = LeaderboardError.Unreachable

        val error = thrown { membership.setVisible(false) }

        assertEquals(LeaderboardError.Unreachable, error)
        assertTrue(membership.isVisible)
    }

    @Test
    fun `should keep the person's old name when the new one is taken`() = runTest {
        val membership = joined()
        api.updateFails = LeaderboardError.UsernameTaken

        val error = thrown { membership.rename(username("whale2")) }

        assertEquals(LeaderboardError.UsernameTaken, error)
        assertEquals("tokenwhale", membership.username?.value)
    }

    @Test
    fun `should show the person under their new name once they rename`() = runTest {
        val membership = joined()

        membership.rename(username("whale2"))

        assertEquals("whale2", membership.username?.value)
        assertEquals("whale2", settings.record?.username)
    }

    // — The globe —

    @Test
    fun `should share the person's country once the server agrees`() = runTest {
        val membership = joined()

        membership.setSharesCountry(true)

        assertTrue(membership.sharesCountry)
        assertEquals(true, settings.record?.sharesCountry)
    }

    @Test
    fun `should keep the person's country unshared when the server can't be reached`() = runTest {
        val membership = joined()
        api.updateFails = LeaderboardError.Unreachable

        val error = thrown { membership.setSharesCountry(true) }

        assertEquals(LeaderboardError.Unreachable, error)
        assertFalse(membership.sharesCountry)
    }

    @Test
    fun `should share the person's country at once when they opt in while joining`() = runTest {
        val membership = membership()

        membership.join(username("tokenwhale"), setOf("claude"), sharesCountry = true)

        assertTrue(membership.sharesCountry)
    }

    @Test
    fun `should show the globe hint to a member who hasn't shared their country, until they dismiss it`() = runTest {
        val membership = joined()
        assertTrue(membership.showsGlobeHint)

        membership.dismissGlobeHint()

        assertFalse(membership.showsGlobeHint)
        assertEquals(true, settings.record?.globeHintDismissed)
    }

    @Test
    fun `should stop showing the globe hint once the person shares their country`() = runTest {
        val membership = joined()

        membership.setSharesCountry(true)

        assertFalse(membership.showsGlobeHint)
    }

    @Test
    fun `should keep the globe hint dismissed after a relaunch`() = runTest {
        joined().dismissGlobeHint()

        assertFalse(membership().showsGlobeHint)
    }

    // — Profile link —

    @Test
    fun `should keep the person's profile link once the server agrees`() = runTest {
        val membership = joined()
        val link = link(ProfileLink.Platform.GITHUB, "octocat")

        membership.setLink(link)

        assertEquals(link, membership.link)
        assertEquals(link, settings.record?.link)
    }

    @Test
    fun `should forget the person's profile link when they remove it`() = runTest {
        val membership = joined()
        membership.setLink(link(ProfileLink.Platform.X, "jack"))

        membership.setLink(null)

        assertNull(membership.link)
        assertNull(settings.record?.link)
    }

    @Test
    fun `should keep no profile link when the server refuses it`() = runTest {
        val membership = joined()
        api.updateFails = LeaderboardError.Rejected("That isn't a github handle.")

        val error = thrown { membership.setLink(link(ProfileLink.Platform.GITHUB, "octocat")) }

        assertEquals(LeaderboardError.Rejected("That isn't a github handle."), error)
        assertNull(membership.link)
    }

    @Test
    fun `should keep a profile link the person adds while joining`() = runTest {
        val membership = membership()
        val link = link(ProfileLink.Platform.INSTAGRAM, "boxcee.codes")

        membership.join(username("tokenwhale"), setOf("claude"), link = link)

        assertEquals(link, membership.link)
    }

    @Test
    fun `should keep the person's profile link after a relaunch`() = runTest {
        joined().setLink(link(ProfileLink.Platform.GITHUB, "octocat"))

        assertEquals("octocat", membership().link?.handle)
    }

    // — Leaving —

    @Test
    fun `should forget this Mac's key and the membership once the server deletes the person`() = runTest {
        val membership = joined()

        membership.leave()

        assertFalse(membership.isJoined)
        assertNull(keys.stored)
        assertNull(settings.record)
    }

    @Test
    fun `should keep the person joined, key and all, when the server doesn't confirm they left`() = runTest {
        val membership = joined()
        api.leaveFails = LeaderboardError.Unreachable

        val error = thrown { membership.leave() }

        assertEquals(LeaderboardError.Unreachable, error)
        assertTrue(membership.isJoined)
        assertNotNull(keys.stored)
    }

    // — On and off —

    @Test
    fun `should be on until the person turns it off`() {
        assertTrue(membership().isOn)
    }

    @Test
    fun `should keep the person's name, key and what they share when they turn it off`() = runTest {
        val membership = joined(setOf("claude", "codex"))

        membership.turnOff()

        assertFalse(membership.isOn)
        assertTrue(membership.isJoined)
        assertEquals("tokenwhale", membership.username?.value)
        assertEquals(setOf("claude", "codex"), membership.sharing)
        assertNotNull(keys.stored)
    }

    @Test
    fun `should stay off after a relaunch`() {
        membership().turnOff()

        assertFalse(membership().isOn)
    }

    @Test
    fun `should stay off after the person leaves`() = runTest {
        val membership = joined()
        membership.turnOff()

        membership.leave()

        assertFalse(membership.isOn)
        assertFalse(membership().isOn)
    }

    @Test
    fun `should be on again once the person turns it back on`() {
        val membership = membership()
        membership.turnOff()

        membership.turnOn()

        assertTrue(membership.isOn)
        assertTrue(membership().isOn)
    }

    // — What the UI follows —

    @Test
    fun `should tell the UI something changed after every change`() = runTest {
        val membership = membership()
        val before = membership.revision.value

        membership.turnOff()

        assertNotEquals(before, membership.revision.value)
    }
}
