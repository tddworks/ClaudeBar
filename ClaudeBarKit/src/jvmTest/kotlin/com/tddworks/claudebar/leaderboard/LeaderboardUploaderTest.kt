package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.date
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.stat
import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.username
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class LeaderboardUploaderTest {
    private val api = FakeLeaderboardAPI()
    private val keys = InMemorySigningKeyStore()
    private val settings = InMemoryLeaderboardSettings()
    private val logs = FakeTokenLogs()
    private val calendar = LeaderboardFixtures.calendar
    private val now = date(4, hour = 15)

    private fun membership() = LeaderboardMembership(api, keys, settings, logs, calendar, JvmRandomBytes)

    private fun uploader(membership: LeaderboardMembership) = LeaderboardUploader(membership, logs, api, calendar, now = { now })

    private suspend fun joined() = membership().also { it.join(username("tokenwhale"), setOf("claude")) }

    @Test
    fun `should send the last thirty days the first time`() = runTest {
        val membership = joined()
        logs.logins = listOf(LoginDays("claude", listOf(stat(day = 4, input = 10))))

        uploader(membership).uploadDue()

        assertEquals(DayRange.last(30, now, calendar), logs.askedFor)
        assertEquals(now, membership.lastUploadSeconds)
        assertEquals(now, settings.record?.lastUploadSeconds)
    }

    @Test
    fun `should send from the day of the last upload on`() = runTest {
        val membership = joined()
        membership.recordUpload(date(3, hour = 23))

        uploader(membership).uploadDue()

        assertEquals(DayRange.of(date(3), now, calendar), logs.askedFor)
    }

    @Test
    fun `should catch up thirty days at most when the Mac slept for weeks`() = runTest {
        val membership = joined()
        membership.recordUpload(date(1, month = 8))

        uploader(membership).uploadDue()

        assertEquals(DayRange.last(30, now, calendar), logs.askedFor)
    }

    @Test
    fun `should keep where it was and say why when an upload can't reach the server`() = runTest {
        val membership = joined()
        logs.logins = listOf(LoginDays("claude", listOf(stat(day = 4, input = 10))))
        api.uploadFails = LeaderboardError.Unreachable
        val uploader = uploader(membership)

        uploader.uploadDue()

        assertNull(membership.lastUploadSeconds)
        assertEquals(LeaderboardError.Unreachable, uploader.lastError)
    }

    @Test
    fun `should clear the last error once an upload goes through`() = runTest {
        val membership = joined()
        logs.logins = listOf(LoginDays("claude", listOf(stat(day = 4, input = 10))))
        api.uploadFails = LeaderboardError.Unreachable
        val uploader = uploader(membership)
        uploader.uploadDue()

        api.uploadFails = null
        uploader.uploadDue()

        assertNull(uploader.lastError)
        assertEquals(now, membership.lastUploadSeconds)
    }

    @Test
    fun `should forget the membership and this Mac's key when the server no longer knows the person`() = runTest {
        val membership = joined()
        logs.logins = listOf(LoginDays("claude", listOf(stat(day = 4, input = 10))))
        api.uploadFails = LeaderboardError.Unauthorized

        uploader(membership).uploadDue()

        assertFalse(membership.isJoined)
        assertNull(keys.stored)
        assertNull(settings.record)
    }

    @Test
    fun `should count as up to date when there is nothing to send`() = runTest {
        val membership = joined()

        uploader(membership).uploadDue()

        assertEquals(now, membership.lastUploadSeconds)
    }

    @Test
    fun `should not upload again within an hour of the last upload`() = runTest {
        val membership = joined()
        val last = now - 59 * 60
        membership.recordUpload(last)

        uploader(membership).uploadDue()

        assertNull(logs.askedFor)
        assertEquals(last, membership.lastUploadSeconds)
    }

    @Test
    fun `should upload again once the last upload is an hour old`() = runTest {
        val membership = joined()
        membership.recordUpload(now - 60 * 60)

        uploader(membership).uploadDue()

        assertEquals(now, membership.lastUploadSeconds)
    }

    @Test
    fun `should upload at once when the person asks, even within the hour`() = runTest {
        val membership = joined()
        membership.recordUpload(now - 5 * 60)

        uploader(membership).uploadNow()

        assertEquals(DayRange.of(date(4), now, calendar), logs.askedFor)
        assertEquals(now, membership.lastUploadSeconds)
    }

    @Test
    fun `should read and send nothing when the person hasn't joined`() = runTest {
        uploader(membership()).uploadDue()

        assertNull(logs.askedFor)
    }

    // — On and off —

    @Test
    fun `should read and send nothing, and keep where it stopped, while the Leaderboard is off`() = runTest {
        val membership = joined()
        membership.recordUpload(date(2))
        membership.turnOff()

        uploader(membership).uploadNow()

        assertNull(logs.askedFor)
        assertEquals(date(2), membership.lastUploadSeconds)
    }

    @Test
    fun `should catch up from where it stopped once the Leaderboard is back on`() = runTest {
        val membership = joined()
        membership.recordUpload(date(2))
        membership.turnOff()
        uploader(membership).uploadDue()

        membership.turnOn()
        uploader(membership).uploadDue()

        assertEquals(DayRange.of(date(2), now, calendar), logs.askedFor)
        assertEquals(now, membership.lastUploadSeconds)
    }
}
