package com.tddworks.claudebar.leaderboard

/**
 * What is remembered of a membership between launches. The private key is not here: it lives in
 * the [SigningKeyStore]. What is shared is kept sorted, so two records of one membership are equal.
 */
internal class LeaderboardRecord(
    val username: String,
    sharing: Collection<String>,
    val visible: Boolean,
    val lastUploadSeconds: Double?,
    val sharesCountry: Boolean = false,
    val globeHintDismissed: Boolean = false,
    val link: ProfileLink? = null,
) {
    val sharing: List<String> = sharing.sorted()

    private val fields get() = listOf(username, sharing, visible, lastUploadSeconds, sharesCountry, globeHintDismissed, link)

    override fun equals(other: Any?) = other is LeaderboardRecord && other.fields == fields

    override fun hashCode() = fields.hashCode()

    override fun toString() = "LeaderboardRecord(${fields.joinToString()})"
}

/** The leaderboard's settings. A destination's own repository, beside Notify!'s, never under the providers' settings. */
internal interface LeaderboardSettingsRepository {
    fun leaderboardRecord(): LeaderboardRecord?

    /** `null` forgets the membership. */
    fun saveLeaderboardRecord(record: LeaderboardRecord?)

    /** Whether ClaudeBar takes part in the Leaderboard at all. Kept apart from the record, so it holds before joining and after leaving. */
    fun isLeaderboardOn(): Boolean

    fun setLeaderboardOn(on: Boolean)
}
