package com.tddworks.claudebar.leaderboard

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class UsernameTest {
    @Test
    fun `should accept every name the shared rule allows`() {
        for (text in LeaderboardVectors.load().usernames.valid) {
            assertEquals(text, Username.of(text)?.value, text)
        }
    }

    @Test
    fun `should refuse every name the shared rule refuses`() {
        for (text in LeaderboardVectors.load().usernames.invalid) {
            assertNull(Username.of(text), text)
        }
    }

    @Test
    fun `should show a username with its at sign`() {
        assertEquals("@tokenwhale", Username.of("tokenwhale").toString())
    }
}
