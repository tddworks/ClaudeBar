package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.calendar
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.date
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.username
import com.tddworks.claudebar.providers.Outcome
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LeaderboardTest {
    private val api = FakeLeaderboardAPI()
    private val logs = FakeTokenLogs(setOf("claude"))

    private fun TestScope.leaderboard(): Leaderboard {
        val membership = LeaderboardMembership(api, InMemorySigningKeyStore(), InMemoryLeaderboardSettings(), logs, calendar, JvmRandomBytes)
        val uploader = LeaderboardUploader(membership, logs, api, calendar, now = { date(12) })
        return Leaderboard(membership, uploader, api, logs, calendar, emptyFlow(), now = { date(12) }, scope = backgroundScope)
    }

    @Test
    fun `should say the name is taken, and leave the person outside, when joining is refused`() = runTest {
        api.joinFails = LeaderboardError.UsernameTaken
        val leaderboard = leaderboard()

        val outcome = leaderboard.join(username("tokenwhale"), setOf("claude"), sharesCountry = false, link = null)

        assertEquals(Outcome.Refused("That username is taken. Try another."), outcome)
        assertFalse(leaderboard.membership.isJoined)
    }

    @Test
    fun `should join the person when the server accepts the name`() = runTest {
        val leaderboard = leaderboard()

        val outcome = leaderboard.join(username("tokenwhale"), setOf("claude"), sharesCountry = false, link = null)

        assertEquals(Outcome.Done(Unit), outcome)
        assertTrue(leaderboard.membership.isJoined)
    }

    @Test
    fun `should say the person hasn't joined when they rename before joining`() = runTest {
        val outcome = leaderboard().rename(username("whale"))

        assertEquals(Outcome.Refused("You haven't joined the leaderboard."), outcome)
    }

    @Test
    fun `should say the board can't be reached when the server is down`() = runTest {
        val down = object : LeaderboardAPI by api {
            override suspend fun board(view: BoardView): List<Standing> = throw LeaderboardError.Unreachable
        }
        val membership = LeaderboardMembership(down, InMemorySigningKeyStore(), InMemoryLeaderboardSettings(), logs, calendar, JvmRandomBytes)
        val leaderboard = Leaderboard(
            membership, LeaderboardUploader(membership, logs, down, calendar) { date(12) }, down, logs, calendar,
            emptyFlow(), now = { date(12) }, scope = backgroundScope,
        )

        val outcome = leaderboard.board(BoardView(BoardPeriod.TODAY))

        assertEquals(Outcome.Refused("The leaderboard can't be reached right now."), outcome)
    }

    @Test
    fun `should save what the server holds about the person, with every uploaded day, when they export their data`() = runTest {
        val leaderboard = leaderboard()
        leaderboard.join(username("tokenwhale"), setOf("claude"), sharesCountry = false, link = null)
        api.summary = MemberSummary(
            standing = Standing(rank = 3, username = "tokenwhale", total = 1200),
            days = listOf(DailyTokens("claude", "2026-10-06", 1000, 200, 0, 0, 0)),
            visible = true,
        )

        val exported = (leaderboard.exportMyData() as Outcome.Done).value

        assertTrue(exported.contains("\"username\" : \"tokenwhale\""))
        assertTrue(exported.contains("\"day\" : \"2026-10-06\""))
        assertTrue(exported.contains("\"shareCountry\" : false"))
    }
}
