package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.link
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class ProfileLinkTest {
    @Test
    fun `should accept every profile handle the shared rules allow`() {
        for ((platform, handle) in LeaderboardVectors.load().links.valid) {
            assertNotNull(ProfileLink.of(requireNotNull(ProfileLink.Platform.of(platform)), handle), "$platform $handle")
        }
    }

    @Test
    fun `should refuse every profile handle the shared rules refuse`() {
        for ((name, handle) in LeaderboardVectors.load().links.invalid) {
            val platform = ProfileLink.Platform.of(name) ?: continue // an unknown platform can't even be named
            assertNull(ProfileLink.of(platform, handle), "$name $handle")
        }
    }

    @Test
    fun `should link to the platform's own address and the handle, never anything typed`() {
        assertEquals("https://github.com/octocat", link(ProfileLink.Platform.GITHUB, "octocat").url)
        assertEquals("https://x.com/jack", link(ProfileLink.Platform.X, "jack").url)
        assertEquals("https://instagram.com/a.b_c", link(ProfileLink.Platform.INSTAGRAM, "a.b_c").url)
    }

    @Test
    fun `should accept a handle the person typed with an at sign or spaces around it`() {
        assertEquals("jack", ProfileLink.typed(" @jack ", ProfileLink.Platform.X)?.handle)
        assertNull(ProfileLink.of(ProfileLink.Platform.X, "@jack"))
    }

    @Test
    fun `should send a profile link as just a platform and a handle`() {
        val json = LeaderboardWire.encode(link(ProfileLink.Platform.X, "jack"))

        assertEquals(JsonObject(mapOf("platform" to JsonPrimitive("x"), "handle" to JsonPrimitive("jack"))), json)
    }
}
