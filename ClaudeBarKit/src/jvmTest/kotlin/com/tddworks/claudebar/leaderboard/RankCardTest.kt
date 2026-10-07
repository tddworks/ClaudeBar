package com.tddworks.claudebar.leaderboard

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class RankCardTest {
    private val view = BoardView(BoardPeriod.SEVEN_DAYS)

    private fun board(count: Int) = (1..count).map { Standing(rank = it, username = "member$it", total = 1_000L - it) }

    private fun rankCard(rank: Int, board: List<Standing>, byProvider: Map<String, Long> = mapOf("claude" to 10)) =
        requireNotNull(RankCard.of(Standing(rank = rank, username = "itshan", total = 3_820, byProvider = byProvider), view, board))

    @Test
    fun `should say how near the top the member is when they're in the top half`() {
        val card = rankCard(rank = 8, board = board(34))

        assertEquals(RankCard.Placement.Top(percent = 24), card.placement)
        assertEquals(34, card.members)
    }

    @Test
    fun `should say the rank among every member when they're in the bottom half`() {
        val card = rankCard(rank = 18, board = board(34))

        assertEquals(RankCard.Placement.Rank(of = 34), card.placement)
    }

    @Test
    fun `should say top 100 when the board is longer than it lists`() {
        val card = rankCard(rank = 40, board = board(100))

        assertEquals(RankCard.Placement.TopHundred, card.placement)
        assertNull(card.members)
    }

    @Test
    fun `should claim no place when the member is ranked beyond the board`() {
        val card = rankCard(rank = 140, board = board(100))

        assertEquals(RankCard.Placement.None, card.placement)
    }

    @Test
    fun `should claim no place when the member is ranked but not listed`() {
        // A hidden member is ranked for themselves but not on the public board.
        val card = rankCard(rank = 12, board = board(10))

        assertEquals(RankCard.Placement.None, card.placement)
        assertNull(card.members)
    }

    @Test
    fun `should offer nothing to share before the member has a rank`() {
        assertNull(RankCard.of(null, view, board(5)))
        assertNull(RankCard.of(Standing(rank = 3, username = "itshan", total = 0), view, board(5)))
    }

    @Test
    fun `should show the providers by their share, largest first, leaving out the ones with none`() {
        val card = rankCard(rank = 2, board = board(5), byProvider = mapOf("codex" to 1, "claude" to 3, "mistral" to 0))

        assertEquals(listOf(RankCard.MixShare("claude", 75), RankCard.MixShare("codex", 25)), card.mix)
    }

    @Test
    fun `should leave out a provider whose share rounds to none`() {
        val card = rankCard(rank = 2, board = board(5), byProvider = mapOf("claude" to 996, "codex" to 4))

        assertEquals(listOf(RankCard.MixShare("claude", 100)), card.mix)
    }

    @Test
    fun `should keep the board view the rank was read in`() {
        val codex = BoardView(BoardPeriod.THIRTY_DAYS, provider = "codex")
        val card = requireNotNull(RankCard.of(Standing(rank = 1, username = "itshan", total = 5), codex, board(3)))

        assertEquals(codex, card.view)
    }

    @Test
    fun `should size each shape for where it gets posted`() {
        assertEquals(1080 to 1080, RankCard.Shape.SQUARE.let { it.width to it.height })
        assertEquals(1200 to 630, RankCard.Shape.WIDE.let { it.width to it.height })
    }
}
