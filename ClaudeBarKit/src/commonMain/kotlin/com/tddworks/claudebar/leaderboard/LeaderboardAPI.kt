package com.tddworks.claudebar.leaderboard

/** *TODAY · 7 DAYS · 30 DAYS* — the periods a board can be read over. Closed. */
internal enum class BoardPeriod(val rawValue: String, val label: String) {
    TODAY("today", "Today"),
    SEVEN_DAYS("7d", "7 days"),
    THIRTY_DAYS("30d", "30 days"),
}

/** A period and, optionally, one provider: `7 days · Claude`. A rank only means something within one view. */
internal data class BoardView(
    val period: BoardPeriod,
    /** `null` is every provider. */
    val provider: String? = null,
)

/** One member's place in one board view. */
internal data class Standing(
    val rank: Int,
    val username: String,
    val total: Long,
    val input: Long = 0,
    val output: Long = 0,
    val cache: Long = 0,
    /** Tokens per provider, for the mix bar. */
    val byProvider: Map<String, Long> = emptyMap(),
    /** The member's profile link, when they added one. Not verified. */
    val link: ProfileLink? = null,
) {
    val id: String get() = username
}

/** What the server holds about you: your standing in a view, whether you're shown, whether your country is on the globe, and every day you uploaded. */
internal data class MemberSummary(
    val standing: Standing?,
    val days: List<DailyTokens>,
    val visible: Boolean,
    val sharesCountry: Boolean = false,
    /** The country the server keeps for the globe, when you opted in. */
    val country: String? = null,
    val link: ProfileLink? = null,
)

/** A change to your membership on the server; fields left `null` stay as they are. */
internal data class MemberChange(
    val username: String? = null,
    val visible: Boolean? = null,
    val sharesCountry: Boolean? = null,
    val link: LinkChange? = null,
) {
    /** A profile link to set, or to remove — distinct from leaving it as it is. */
    sealed class LinkChange {
        data class Set(val link: ProfileLink) : LinkChange()
        data object Remove : LinkChange()
    }
}

/**
 * *WHERE CLAUDEBAR IS USED* — every country opted-in members share. Members and tokens only where
 * at least three are ([countries]); the rest are named without a number ([present]), so no
 * number is one person's own.
 */
internal data class GlobeSummary(val countries: List<Country>, val present: List<String>) {
    data class Country(val country: String, val members: Long, val tokens: Long)

    /** Every country on the globe, with numbers or without. */
    val countryCount: Int get() = countries.size + present.size
}

/** Who signs a request: the name and the key only this Mac holds. */
internal data class MemberCredentials(val username: Username, val key: SigningKey)

/** Why a leaderboard call failed, in the words the card shows. */
internal sealed class LeaderboardError(message: String) : Exception(message) {
    data object UsernameTaken : LeaderboardError("That username is taken. Try another.")

    data class NotShareable(val provider: String) :
        LeaderboardError("$provider has no token logs on this Mac, so it can't be shared.")

    data object NothingShared : LeaderboardError("Pick at least one provider to share.")

    data object NotJoined : LeaderboardError("You haven't joined the leaderboard.")

    /** The server refused the signature: the key no longer matches the name. */
    data object Unauthorized : LeaderboardError("The leaderboard didn't accept this Mac's key for your username.")

    data class Rejected(val reason: String) : LeaderboardError(reason)

    data object Unreachable : LeaderboardError("The leaderboard can't be reached right now.")
}

/** The leaderboard server. Every call but [join], [board] and [globe] is signed. Failures throw [LeaderboardError]. */
internal interface LeaderboardAPI {
    suspend fun join(username: String, publicKey: String)
    suspend fun upload(days: List<DailyTokens>, credentials: MemberCredentials)
    suspend fun me(view: BoardView, credentials: MemberCredentials): MemberSummary
    suspend fun update(change: MemberChange, credentials: MemberCredentials)
    suspend fun leave(credentials: MemberCredentials)
    suspend fun board(view: BoardView): List<Standing>
    suspend fun globe(view: BoardView): GlobeSummary
}
