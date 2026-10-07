package com.tddworks.claudebar.leaderboard

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class GlobeSummaryTest {
    @Test
    fun `should count every country on the globe, with numbers or without`() {
        val globe = GlobeSummary(listOf(GlobeSummary.Country("NL", members = 3, tokens = 300)), present = listOf("GR", "VN"))

        assertEquals(3, globe.countryCount)
    }

    @Test
    fun `should count no countries when no one shares theirs`() {
        assertEquals(0, GlobeSummary(emptyList(), emptyList()).countryCount)
    }
}
