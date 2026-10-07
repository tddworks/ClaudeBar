package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.io.IOException
import java.util.Collections

/** Grok's login file, refresh and accounts through the definition. */
class GrokExecutionTest {
    private val folders = mutableListOf<File>()

    /** What a request carried that the test didn't expect — checked after every test. */
    private val wrongRequests: MutableList<String> = Collections.synchronizedList(mutableListOf())

    @AfterEach
    fun cleanUp() {
        folders.forEach { it.deleteRecursively() }
        assertEquals(emptyList<String>(), wrongRequests)
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    private fun network(answer: (HttpCall) -> Response): NetworkClient = object : NetworkClient {
        override suspend fun send(call: HttpCall): Response = answer(call)
    }

    private fun make(home: File, network: NetworkClient = network { Response(500, body = ByteArray(0)) }): Provider {
        val connections = testDataSources(network = network, home = home.path, now = { System.currentTimeMillis() / 1000.0 })
        return Provider(
            definition = TestDefinitions.builtIn("grok"), settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, "grok", null, TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), paths = HomePaths(home.path), isExecutable = { true }, locate = { it },
        )
    }

    private fun saved(key: String, home: File): String? {
        val json = Json.parseToJsonElement(File(home, ".grok/auth.json").readText()).jsonObject
        return ((json["https://auth.x.ai::client-123"] as? JsonObject)?.get(key) as? JsonPrimitive)?.content
    }

    private fun makeTemporaryDirectory(): File = TestDefinitions.folder("grok-probe-tests").also { folders += it }

    private fun createAuthFile(
        directory: File,
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAt: String = "2099-01-01T00:00:00.000000Z",
    ) {
        val grokDir = File(directory, ".grok").apply { mkdirs() }
        val entry = buildMap<String, JsonElement> {
            put("key", JsonPrimitive(accessToken))
            put("auth_mode", JsonPrimitive("oidc"))
            put("email", JsonPrimitive("user@example.com"))
            put("expires_at", JsonPrimitive(expiresAt))
            put("oidc_issuer", JsonPrimitive("https://auth.x.ai"))
            put("oidc_client_id", JsonPrimitive("client-123"))
            if (refreshToken != null) put("refresh_token", JsonPrimitive(refreshToken))
        }
        File(grokDir, "auth.json").writeText(JsonObject(mapOf("https://auth.x.ai::client-123" to JsonObject(entry))).toString())
    }

    private val billingJSON = """
        {
          "config": {
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-07-23T05:09:24.881042+00:00",
              "end": "2026-07-30T05:09:24.881042+00:00"
            },
            "creditUsagePercent": 96.0,
            "productUsage": [
              {"product": "GrokBuild", "usagePercent": 84.0}
            ]
          }
        }
    """.trimIndent()

    private fun response(status: Int, body: String = "") = Response(status, body = body.encodeToByteArray())

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    private fun assertSessionExpired(hint: String, outcome: RefreshOutcome) {
        val error = outcome.failure()
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals(hint, (error as UsageError.SessionExpired).hint)
    }

    // isAvailable

    @Test
    fun `should be available when the Grok CLI has a login on this Mac`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir)

        assertTrue(make(tempDir).isPlainAvailable())
    }

    @Test
    fun `should be unavailable when the Grok CLI has no login on this Mac`() {
        assertFalse(make(makeTemporaryDirectory()).isPlainAvailable())
    }

    // Refresh

    @Test
    fun `should ask to sign in when the Grok CLI has no login`() {
        assertEquals(UsageError.AuthenticationRequired, make(makeTemporaryDirectory()).refreshPlain().failure())
    }

    @Test
    fun `should show the login's email, weekly credits and Build when Grok answers`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir)

        val snapshot = make(tempDir, network { response(200, billingJSON) }).refreshPlain().usage()

        assertEquals("grok", snapshot.providerId)
        assertEquals("user@example.com", snapshot.accountEmail)
        assertEquals(4.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(16.0, snapshot.quota(QuotaType.ModelSpecific("Build"))?.percentRemaining)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should renew a refused login, show the usage and save the new tokens back to Grok's file`(rejectedStatus: Int) {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir, accessToken = "stale-token")
        val refreshResponse = """{"access_token": "fresh-token", "refresh_token": "fresh-refresh-token", "expires_in": 3600}"""

        val network = network { call ->
            when {
                call.url.contains("oauth2/token") -> response(200, refreshResponse)
                (call.header("Authorization") ?: "").contains("fresh-token") -> response(200, billingJSON)
                else -> response(rejectedStatus)
            }
        }

        val snapshot = make(tempDir, network).refreshPlain().usage()

        assertEquals(4.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
        // The refreshed token was written back for the next provider
        assertEquals("fresh-token", saved("key", tempDir))
        assertEquals("fresh-refresh-token", saved("refresh_token", tempDir))
    }

    @Test
    fun `should renew an expired login before asking and save it back`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir, accessToken = "expired-token", expiresAt = "2020-01-01T00:00:00.000000Z")
        val refreshResponse = """{"access_token": "fresh-token", "expires_in": 3600}"""

        val network = network { call -> if (call.url.contains("oauth2/token")) response(200, refreshResponse) else response(200, billingJSON) }

        val snapshot = make(tempDir, network).refreshPlain().usage()

        assertEquals(2, snapshot.quotas.size)
        assertEquals("fresh-token", saved("key", tempDir))
    }

    @Test
    fun `should ask to run grok login again when the login can't be renewed`() {
        val tempDir = makeTemporaryDirectory()
        // Expired token forces a refresh; the refresh endpoint rejects it
        createAuthFile(tempDir, expiresAt = "2020-01-01T00:00:00.000000Z")

        val provider = make(tempDir, network { response(400, """{"error": "invalid_grant"}""") })

        assertSessionExpired("Run `grok login` in terminal to log in again.", provider.refreshPlain())
    }

    @Test
    fun `should ask to run grok login again when the renewed login is still refused`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir)
        val refreshResponse = """{"access_token": "fresh-token", "expires_in": 3600}"""

        val provider = make(tempDir, network { call -> if (call.url.contains("oauth2/token")) response(200, refreshResponse) else response(401) })

        assertSessionExpired("Run `grok login` in terminal to log in again.", provider.refreshPlain())
    }

    @Test
    fun `should fail when the network is down`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir)

        make(tempDir, network { throw IOException("The Internet connection appears to be offline.") }).refreshPlain().failure()
    }

    @Test
    fun `should report the HTTP error when Grok answers 500`() {
        val tempDir = makeTemporaryDirectory()
        createAuthFile(tempDir)

        assertEquals(UsageError.ExecutionFailed("HTTP error: 500"), make(tempDir, network { response(500) }).refreshPlain().failure())
    }

    @Test
    fun `should read each added login from its own Grok folder, keep its name, and never fall back to the default login`() {
        val personal = makeTemporaryDirectory()
        val work = makeTemporaryDirectory()
        createAuthFile(personal, accessToken = "personal-token")
        createAuthFile(work, accessToken = "work-token")
        val network = network { call ->
            val token = call.header("Authorization")
            if (token != "Bearer personal-token" && token != "Bearer work-token") wrongRequests += "token $token"
            val used = if (token == "Bearer personal-token") 10 else 60
            response(200, """{"creditUsagePercent":$used}""")
        }
        val definition = TestDefinitions.builtIn("grok")
        val settings = InMemoryProviderSettings()
        val connections = testDataSources(network = network, home = personal.path, now = { System.currentTimeMillis() / 1000.0 })
        val factory = {
            Provider(
                definition = definition, settings = settings, saved = settings.accounts("grok"),
                makeDataSource = { source, _ -> connections.make(source, "grok", null, TestDefinitions.builtIns::script) },
                folders = InMemoryLoginFolders(), paths = HomePaths(personal.path), isExecutable = { true }, locate = { it },
            )
        }
        val provider = factory()
        assertEquals("Grok", provider.defaultAccount.displayName)
        assertTrue(provider.accounts.add(mapOf("directory" to "relative/path")) is Outcome.Refused)
        val account = provider.accounts.add(mapOf("directory" to File(work, ".grok").path)).done()
        provider.accounts.rename(account, "Work")
        assertEquals(90.0, provider.refreshPlain().usage().quotas[0].percentRemaining)
        assertEquals(40.0, provider.refreshNow(account).usage().quotas[0].percentRemaining)
        val restored = factory()
        val restoredWork = restored.accounts.firstOrNull { it.id == account.id }
        assertNotNull(restoredWork)
        assertEquals("Work", restoredWork!!.displayName)
        assertEquals(40.0, restored.refreshNow(restoredWork).usage().quotas[0].percentRemaining)
        File(work, ".grok/auth.json").delete()
        assertEquals(UsageError.AuthenticationRequired, restored.refreshNow(restoredWork).failure())
        assertEquals(90.0, restored.refreshPlain().usage().quotas[0].percentRemaining)
        restored.accounts.remove(restoredWork)
        assertTrue(work.exists())
        assertTrue(settings.accounts("grok").isEmpty())
    }

    @Test
    fun `should renew a login with its own issuer, and keep its renewal token when none comes back`() {
        val root = makeTemporaryDirectory()
        createAuthFile(root, accessToken = "old", refreshToken = "refresh&a+b", expiresAt = "2020-01-01T00:00:00Z")
        val file = File(root, ".grok/auth.json")
        val document = Json.parseToJsonElement(file.readText()).jsonObject
        val entry = document.getValue("https://auth.x.ai::client-123").jsonObject
        val changed = entry + ("oidc_issuer" to JsonPrimitive("https://tenant.test/base/")) - "oidc_client_id"
        file.writeText(JsonObject(mapOf("https://auth.x.ai::client-123" to JsonObject(changed))).toString())
        val network = network { call ->
            if (call.method == "POST") {
                if (call.url != "https://tenant.test/base/oauth2/token") wrongRequests += "renewal url ${call.url}"
                if (call.header("Content-Type") != "application/x-www-form-urlencoded") wrongRequests += "content type ${call.header("Content-Type")}"
                val body = call.body?.decodeToString() ?: ""
                if (!body.contains("refresh_token=refresh%26a%2Bb")) wrongRequests += "renewal body $body"
                if (body.contains("client_id=")) wrongRequests += "client id in $body"
                return@network response(200, """{"access_token":"fresh","refresh_token":"","expires_in":3600}""")
            }
            if (call.header("Authorization") != "Bearer fresh") wrongRequests += "token ${call.header("Authorization")}"
            response(200, billingJSON)
        }
        make(root, network).refreshPlain()
        assertEquals("fresh", saved("key", root))
        assertEquals("refresh&a+b", saved("refresh_token", root))
    }

    @Test
    fun `should ask for the key again when a login with nothing to renew with is refused`() {
        val root = makeTemporaryDirectory()
        createAuthFile(root, refreshToken = null)
        val provider = make(root, network { response(401) })
        // Nothing to refresh with, as for any API-key login: Key needed.
        assertEquals(UsageError.AuthenticationRequired, provider.refreshPlain().failure())
    }
}
