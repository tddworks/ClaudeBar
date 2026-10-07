package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.AccountTier
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Where the `api` data source finds Claude's OAuth credentials — the file, then the Keychain,
 * then `CLAUDE_CODE_OAUTH_TOKEN` — and how a refreshed token is written back. What the old
 * loader returned is observed here as `hasKey` and the request's `Authorization` header.
 */
class ClaudeCredentialTest {
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    private val usageOK = """{ "five_hour": { "utilization": 10.0 } }"""

    /** The `Authorization` header the usage request carried. */
    private fun authorization(): String? {
        var sent: String? = null
        claude.answer { call ->
            if (call.isClaudeTokenRequest) {
                claudeResponse(400, body = """{"error":"invalid_grant"}""")
            } else {
                sent = call.claudeAuthorization
                claudeResponse(200, body = usageOK)
            }
        }
        claude.fetchUsage(claude.dataSource("api"))
        return sent
    }

    private fun writeRawCredentials(text: String) {
        val directory = File(claude.home, ".claude").apply { mkdirs() }
        File(directory, ".credentials.json").writeText(text)
    }

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.content

    // The credentials file

    @Test
    fun `should find no Claude login when the credentials file does not exist`() {
        assertFalse(claude.dataSource("api").hasKey)
    }

    @Test
    fun `should show the usage and plan of the login in the credentials file`() {
        claude.writeCredentials(
            accessToken = "my-access-token",
            refreshToken = "my-refresh-token",
            expiresAt = (claude.now + 3600) * 1000,
            subscriptionType = "claude_max",
        )
        claude.answer { call ->
            if (call.claudeAuthorization == "Bearer my-access-token") claudeResponse(200, body = usageOK) else claudeResponse(500)
        }

        val snapshot = claude.fetchUsage(claude.dataSource("api"))

        assertEquals(90.0, snapshot.quotas.first().percentRemaining)
        assertEquals(AccountTier.ClaudeMax, snapshot.accountTier)
    }

    @Test
    fun `should renew an expired login with the refresh token the credentials file holds`() {
        claude.writeCredentials(refreshToken = "my-refresh-token", expiresAt = (claude.now - 3600) * 1000)
        claude.answer { call ->
            if (call.isClaudeTokenRequest) {
                val body = call.body?.let { runCatching { Json.parseToJsonElement(it.decodeToString()) as JsonObject }.getOrNull() }
                if (body?.text("refresh_token") == "my-refresh-token") {
                    claudeResponse(200, body = """{ "access_token": "new-token", "expires_in": 3600 }""")
                } else {
                    claudeResponse(400, body = """{"error":"invalid_grant"}""")
                }
            } else {
                claudeResponse(200, body = usageOK)
            }
        }

        claude.fetchUsage(claude.dataSource("api"))

        assertEquals("new-token", claude.readCredentials().text("accessToken"))
    }

    @Test
    fun `should find no Claude login when the file's access token is empty`() {
        claude.writeCredentials(accessToken = "", refreshToken = "refresh")

        assertFalse(claude.dataSource("api").hasKey)
    }

    @Test
    fun `should find no Claude login when the credentials file is not JSON`() {
        writeRawCredentials("not valid json")

        assertFalse(claude.dataSource("api").hasKey)
    }

    @Test
    fun `should find no Claude login when the credentials file holds no Claude login`() {
        writeRawCredentials("""{"someOtherKey":"value"}""")

        assertFalse(claude.dataSource("api").hasKey)
    }

    // Writing back

    @Test
    fun `should use the renewed login next time once it is saved back`() {
        claude.writeCredentials(accessToken = "old-token", refreshToken = "old-refresh", expiresAt = (claude.now - 3600) * 1000)
        val refreshed = """{ "access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 3600 }"""
        var sent: String? = null
        claude.answer { call ->
            if (call.isClaudeTokenRequest) {
                claudeResponse(200, body = refreshed)
            } else {
                sent = call.claudeAuthorization
                claudeResponse(200, body = usageOK)
            }
        }
        claude.fetchUsage(claude.dataSource("api"))

        // A new data source reads the file afresh.
        claude.fetchUsage(claude.dataSource("api"))

        assertEquals("Bearer new-token", sent)
        val saved = claude.readCredentials()
        assertEquals("new-token", saved.text("accessToken"))
        assertEquals("new-refresh", saved.text("refreshToken"))
    }

    @Test
    fun `should keep what Claude wrote in the credentials file when the renewed login is saved back`() {
        // expiresAt is long past, so the token is refreshed.
        claude.writeCredentials(
            accessToken = "old-token",
            refreshToken = "old-refresh",
            expiresAt = 1_748_276_587_173.0,
            extra = mapOf("scopes" to JsonArray(listOf(JsonPrimitive("user:inference"), JsonPrimitive("user:profile")))),
        )
        claude.answer { call ->
            if (call.isClaudeTokenRequest) claudeResponse(200, body = """{ "access_token": "new-token", "expires_in": 3600 }""")
            else claudeResponse(200, body = usageOK)
        }

        claude.fetchUsage(claude.dataSource("api"))

        val saved = claude.readCredentials()
        assertEquals("new-token", saved.text("accessToken"))
        assertEquals(JsonArray(listOf(JsonPrimitive("user:inference"), JsonPrimitive("user:profile"))), saved["scopes"])
        val expiresAt = saved["expiresAt"] as JsonPrimitive
        assertFalse(expiresAt.isString)
        assertEquals(true, expiresAt.content.toDoubleOrNull() != null)
    }

    // The Keychain

    @Test
    fun `should use the login in the Keychain when there is no credentials file`() {
        claude.keychainPassword = """{"claudeAiOauth":{"accessToken":"keychain-token","subscriptionType":"claude_pro"}}"""

        assertEquals("Bearer keychain-token", authorization())
    }

    @Test
    fun `should read a Keychain login an older build saved hex-encoded`() {
        val json = """{"claudeAiOauth":{"accessToken":"hex-token"}}"""
        claude.keychainPassword = json.toByteArray().joinToString("") { "%02x".format(it) }

        assertEquals("Bearer hex-token", authorization())
    }

    @Test
    fun `should prefer the credentials file over the Keychain`() {
        claude.writeCredentials(accessToken = "file-token")
        claude.keychainPassword = """{"claudeAiOauth":{"accessToken":"keychain-token"}}"""

        assertEquals("Bearer file-token", authorization())
    }

    @Test
    fun `should prefer the Keychain over the environment token`() {
        claude.keychainPassword = """{"claudeAiOauth":{"accessToken":"keychain-token"}}"""
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "env-token")

        assertEquals("Bearer keychain-token", authorization())
    }

    // CLAUDE_CODE_OAUTH_TOKEN

    @Test
    fun `should use the environment token when there is no other login`() {
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "my-setup-token")

        assertEquals("Bearer my-setup-token", authorization())
    }

    @Test
    fun `should never renew the environment token or save it to a file`() {
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "my-setup-token")

        // `authorization` answers any refresh with invalid_grant: the fetch succeeding shows none was tried.
        assertEquals("Bearer my-setup-token", authorization())
        assertFalse(File(claude.home, ".claude/.credentials.json").exists())
    }

    @Test
    fun `should use the environment token without its surrounding whitespace and newlines`() {
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "  my-setup-token\n")

        assertEquals("Bearer my-setup-token", authorization())
    }

    @Test
    fun `should prefer the credentials file over the environment token`() {
        // Full-scope credentials from `claude login`
        claude.writeCredentials(accessToken = "file-token", refreshToken = "file-refresh")
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "env-token")

        assertEquals("Bearer file-token", authorization())
    }

    @Test
    fun `should find no Claude login when the environment token is empty`() {
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "")

        assertFalse(claude.dataSource("api").hasKey)
    }

    @Test
    fun `should use the credentials file when the environment token is empty`() {
        claude.writeCredentials(accessToken = "file-token")
        claude.environment = mapOf("CLAUDE_CODE_OAUTH_TOKEN" to "")

        assertEquals("Bearer file-token", authorization())
    }

    @Test
    fun `should use the credentials file when there is no environment token`() {
        claude.writeCredentials(accessToken = "file-token")

        assertEquals("Bearer file-token", authorization())
    }
}
