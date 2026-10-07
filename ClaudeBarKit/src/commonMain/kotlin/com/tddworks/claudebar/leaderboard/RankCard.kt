package com.tddworks.claudebar.leaderboard

import kotlin.math.ceil
import kotlin.math.floor

/**
 * *SHARE MY RANK* — one standing in one board view, as the shared image says it: the rank, where
 * that is on the board, the tokens and the provider mix. Nothing the board doesn't already show,
 * and no other member's name.
 */
@ConsistentCopyVisibility
internal data class RankCard private constructor(
    val rank: Int,
    val username: String,
    val total: Long,
    val view: BoardView,
    /** Largest first; a provider whose share rounds to 0% is left out, as one with no tokens is. */
    val mix: List<MixShare>,
    /** Every member in the view, when the board lists them all and the rank is among them. */
    val members: Int?,
    val placement: Placement,
) {
    /** The image's shape, by where it gets posted. */
    enum class Shape(val id: String, val width: Int, val height: Int) {
        /** X, Instagram and chats. */
        SQUARE("square", 1080, 1080),

        /** The link-card shape, for READMEs and blogs. */
        WIDE("wide", 1200, 630),
    }

    /** Where the rank is on the board, in the words the image prints. */
    sealed class Placement {
        /** *TOP 24%* — in the top half of every member. */
        data class Top(val percent: Int) : Placement()

        /** *#18 OF 34* — in the bottom half. */
        data class Rank(val of: Int) : Placement()

        /** *TOP 100* — on a board longer than it lists. */
        data object TopHundred : Placement()

        /** Ranked, but where among how many isn't known. */
        data object None : Placement()
    }

    /** One provider's share of the tokens, for the mix bar. */
    data class MixShare(val provider: String, val percent: Int)

    companion object {
        /** The most members a board lists. */
        const val LIST_LIMIT = 100

        /** `null` until there's a rank to share: before the first upload, or with no tokens in this view. */
        fun of(standing: Standing?, view: BoardView, board: List<Standing>): RankCard? {
            if (standing == null || standing.total <= 0) return null

            val sum = standing.byProvider.values.sum().toDouble()
            val mix = standing.byProvider.entries
                .filter { it.value > 0 }
                .sortedWith(compareByDescending<Map.Entry<String, Long>> { it.value }.thenBy { it.key })
                .map { MixShare(it.key, floor(it.value / sum * 100 + 0.5).toInt()) }
                .filter { it.percent > 0 }

            val listsEveryone = board.size < LIST_LIMIT
            val members = if (listsEveryone && standing.rank <= board.size) board.size else null
            val placement = when {
                members != null -> if (standing.rank * 2 <= members) {
                    Placement.Top(ceil(standing.rank.toDouble() / members * 100).toInt())
                } else {
                    Placement.Rank(members)
                }
                !listsEveryone && standing.rank <= LIST_LIMIT -> Placement.TopHundred
                else -> Placement.None
            }
            return RankCard(standing.rank, standing.username, standing.total, view, mix, members, placement)
        }
    }
}
