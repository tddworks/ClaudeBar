package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.quotas.DailyUsageStat
import java.security.SecureRandom
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

internal class InMemorySigningKeyStore : SigningKeyStore {
    var stored: ByteArray? = null

    override fun load() = stored
    override fun save(rawKey: ByteArray) { stored = rawKey }
    override fun delete() { stored = null }
}

internal class InMemoryLeaderboardSettings : LeaderboardSettingsRepository {
    var record: LeaderboardRecord? = null
    var isOn = true

    override fun leaderboardRecord() = record
    override fun saveLeaderboardRecord(record: LeaderboardRecord?) { this.record = record }
    override fun isLeaderboardOn() = isOn
    override fun setLeaderboardOn(on: Boolean) { isOn = on }
}

/** This Mac's logs: what each login used, and the range last asked for. */
internal class FakeTokenLogs(override var providersWithLogs: Set<String> = setOf("claude", "codex")) : TokenLogs {
    var logins: List<LoginDays> = emptyList()
    var askedFor: DayRange? = null
        private set

    override suspend fun days(range: DayRange): List<LoginDays> {
        askedFor = range
        return logins
    }
}

/** A server that accepts every call, until a call is told to fail. */
internal class FakeLeaderboardAPI : LeaderboardAPI {
    var joinFails: LeaderboardError? = null
    var uploadFails: LeaderboardError? = null
    var updateFails: LeaderboardError? = null
    var leaveFails: LeaderboardError? = null
    var summary = MemberSummary(standing = null, days = emptyList(), visible = true)
    var standings: List<Standing> = emptyList()
    var globeSummary = GlobeSummary(emptyList(), emptyList())

    override suspend fun join(username: String, publicKey: String) { joinFails?.let { throw it } }
    override suspend fun upload(days: List<DailyTokens>, credentials: MemberCredentials) { uploadFails?.let { throw it } }
    override suspend fun me(view: BoardView, credentials: MemberCredentials) = summary
    override suspend fun update(change: MemberChange, credentials: MemberCredentials) { updateFails?.let { throw it } }
    override suspend fun leave(credentials: MemberCredentials) { leaveFails?.let { throw it } }
    override suspend fun board(view: BoardView) = standings
    override suspend fun globe(view: BoardView) = globeSummary
}

internal object JvmRandomBytes : RandomBytes {
    private val source = SecureRandom()
    override fun bytes(count: Int) = ByteArray(count).also(source::nextBytes)
}

/** A time zone's offset, from the JDK's rules. */
internal fun zoneOffset(zone: String) = UtcOffset { seconds ->
    ZoneId.of(zone).rules.getOffset(Instant.ofEpochMilli((seconds * 1000).toLong())).totalSeconds.toLong()
}

internal object LeaderboardFixtures {
    const val ZONE = "Europe/Amsterdam"
    val calendar = MemberCalendar(zoneOffset(ZONE))

    fun date(day: Int, month: Int = 10, hour: Int = 12): Double =
        ZonedDateTime.of(2026, month, day, hour, 0, 0, 0, ZoneId.of(ZONE)).toEpochSecond().toDouble()

    fun stat(day: Int, input: Long = 0, output: Long = 0, cacheRead: Long = 0) = DailyUsageStat(
        dateSeconds = date(day), totalCostNanos = 0, totalTokens = input + output, workingTime = 0.0, sessionCount = 1,
        inputTokens = input, outputTokens = output, cacheCreationTokens = 0, cacheReadTokens = cacheRead, cachedSavingsNanos = 0,
    )

    fun username(text: String) = requireNotNull(Username.of(text))

    fun link(platform: ProfileLink.Platform, handle: String) = requireNotNull(ProfileLink.of(platform, handle))
}

/** The leaderboard error a command failed with, or null when it went through. */
internal suspend fun thrown(command: suspend () -> Unit): LeaderboardError? = try {
    command()
    null
} catch (e: LeaderboardError) {
    e
}
