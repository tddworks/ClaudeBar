package com.tddworks.claudebar.leaderboard

import com.tddworks.claudebar.leaderboard.LeaderboardFixtures.link
import com.tddworks.claudebar.storage.CredentialRepository
import com.tddworks.claudebar.storage.SettingsFile
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.io.encoding.Base64

/**
 * The membership's record in `settings.json`, and the private key beside the other secrets — in
 * the Keychain, or the fallback store when the Keychain refuses a locally built app.
 */
class LeaderboardStorageTest {
    @TempDir
    lateinit var dir: File

    /** A credential store that keeps what it's given. */
    private class KeepingCredentials : CredentialRepository {
        val values = mutableMapOf<String, String>()
        override fun save(value: String, key: String) { values[key] = value }
        override fun get(key: String) = values[key]
        override fun delete(key: String): Boolean { values.remove(key); return true }
    }

    /** The Keychain as an ad-hoc signed build sees it: every call "succeeds", nothing is kept. */
    private class RefusingCredentials : CredentialRepository {
        override fun save(value: String, key: String) {}
        override fun get(key: String): String? = null
        override fun delete(key: String) = true
    }

    private val file get() = File(dir, "settings.json")

    private fun repository() = JsonLeaderboardSettings(SettingsFile(file.path))

    // — Settings —

    @Test
    fun `should remember the leaderboard membership across reads`() {
        val settings = repository()
        val record = LeaderboardRecord(
            username = "tokenwhale", sharing = listOf("codex", "claude"), visible = false,
            lastUploadSeconds = 1_791_080_000.25, sharesCountry = true, globeHintDismissed = true,
            link = link(ProfileLink.Platform.INSTAGRAM, "boxcee.codes"),
        )

        settings.saveLeaderboardRecord(record)

        assertEquals(record, repository().leaderboardRecord())
    }

    @Test
    fun `should leave nothing of the membership in settings when it is forgotten`() {
        val settings = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord("tokenwhale", listOf("claude"), visible = true, lastUploadSeconds = null))

        settings.saveLeaderboardRecord(null)

        assertNull(settings.leaderboardRecord())
        assertFalse(file.readText().contains("tokenwhale"))
    }

    @Test
    fun `should remember the Leaderboard is off, apart from the membership`() {
        val settings = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord("tokenwhale", listOf("claude"), visible = true, lastUploadSeconds = null))

        settings.setLeaderboardOn(false)
        settings.saveLeaderboardRecord(null)

        assertFalse(settings.isLeaderboardOn())
    }

    @Test
    fun `should count the Leaderboard as on when nothing was saved`() {
        assertTrue(repository().isLeaderboardOn())
    }

    @Test
    fun `should read the membership the Swift app saved, under the same keys`() {
        file.writeText(
            """
            {"leaderboard": {"username": "tokenwhale", "sharing": ["codex", "claude"], "visible": false,
             "lastUpload": 1791080000.5, "sharesCountry": true, "globeHintDismissed": true,
             "linkPlatform": "github", "linkHandle": "octocat", "on": false}}
            """.trimIndent(),
        )

        val settings = repository()

        assertEquals(
            LeaderboardRecord(
                "tokenwhale", listOf("claude", "codex"), visible = false, lastUploadSeconds = 1_791_080_000.5,
                sharesCountry = true, globeHintDismissed = true, link = link(ProfileLink.Platform.GITHUB, "octocat"),
            ),
            settings.leaderboardRecord(),
        )
        assertFalse(settings.isLeaderboardOn())
    }

    @Test
    fun `should write the last upload as plain Unix seconds, as the Swift app did`() {
        repository().saveLeaderboardRecord(LeaderboardRecord("tokenwhale", listOf("claude"), visible = true, lastUploadSeconds = 1_791_080_000.5))

        assertTrue(file.readText().contains("\"lastUpload\" : 1791080000.5"), file.readText())
    }

    // — The key —

    @Test
    fun `should keep the signing key in the Keychain when the Keychain accepts it`() {
        val secure = KeepingCredentials()
        val fallback = KeepingCredentials()
        val store = CredentialSigningKeyStore(secure, fallback)

        store.save(byteArrayOf(1, 2, 3))

        assertArrayEquals(byteArrayOf(1, 2, 3), store.load())
        assertEquals(mapOf("leaderboard-signing-key" to "AQID"), secure.values)
        assertTrue(fallback.values.isEmpty())
        assertTrue(store.isSecure)
    }

    @Test
    fun `should keep the signing key in the fallback store when the Keychain refuses it`() {
        val fallback = KeepingCredentials()
        val store = CredentialSigningKeyStore(RefusingCredentials(), fallback)

        store.save(byteArrayOf(1, 2, 3))

        assertArrayEquals(byteArrayOf(1, 2, 3), store.load())
        assertEquals(1, fallback.values.size)
        assertFalse(store.isSecure)
    }

    @Test
    fun `should forget the signing key from both stores when it is deleted`() {
        val secure = KeepingCredentials()
        val fallback = KeepingCredentials()
        secure.values[CredentialSigningKeyStore.KEY] = Base64.Default.encode(byteArrayOf(9))
        fallback.values[CredentialSigningKeyStore.KEY] = Base64.Default.encode(byteArrayOf(8))
        val store = CredentialSigningKeyStore(secure, fallback)

        store.delete()

        assertNull(store.load())
        assertTrue(secure.values.isEmpty() && fallback.values.isEmpty())
    }
}
