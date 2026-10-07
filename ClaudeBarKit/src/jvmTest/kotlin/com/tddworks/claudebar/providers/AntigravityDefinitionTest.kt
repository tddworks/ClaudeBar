package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.URI
import java.util.Base64
import java.util.Collections

/**
 * Antigravity as data: the running app's own server, found through its process, or — with the
 * app closed — Google's quota with the login it saved in the Keychain. The old probe's
 * fixtures, quota for quota.
 */
class AntigravityDefinitionTest {
    private val processLine = "26416 /Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token 9f808dbe-cb96-4829 --extension_server_port 58445 --app_data_dir antigravity"
    private val lsof = "language 26416 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:42135 (LISTEN)"
    private val summary = """{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"gemini-5h","remainingFraction":0.8,"resetTime":"2025-01-01T05:00:00Z"},{"bucketId":"gemini-weekly","remainingFraction":0.6,"resetTime":"2025-01-07T00:00:00Z"}]},{"displayName":"Claude & others","buckets":[{"bucketId":"3p-5h","remainingFraction":0.4},{"bucketId":"3p-weekly","remainingFraction":0.2},{"bucketId":"gemini-image-5h","remainingFraction":1.0}]}]}"""
    private val userStatus = """{"userStatus":{"email":"user@example.com","planStatus":{"planInfo":{"planName":"Pro"}},"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Claude Sonnet","quotaInfo":{"remainingFraction":0.75,"resetTime":"2025-01-01T00:00:00Z"}},{"label":"Gemini Pro","quotaInfo":{"remainingFraction":0.5,"resetTime":"1735689600"}},{"label":"No Quota Model"}]}}}"""

    private class Seen {
        val requests: MutableList<HttpCall> = Collections.synchronizedList(mutableListOf())
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** [answers]: path suffix → (status, body); anything else is a 404. */
    private fun make(
        running: Boolean = true, answers: Map<String, Pair<Int, String>> = emptyMap(), keychain: String? = null, seen: Seen = Seen(),
    ): Provider {
        val commands = FakeCLIExecutor(path = null) { CLIResult(if (it.binary.endsWith("pgrep")) (if (running) processLine else "") else lsof) }
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                seen.requests += call
                val path = URI(call.url).path ?: ""
                val answer = answers.entries.firstOrNull { path.endsWith(it.key) }?.value ?: return Response(404, body = ByteArray(0))
                return Response(answer.first, body = answer.second.encodeToByteArray())
            }
        }
        val connections = testDataSources(
            network = network, cli = commands,
            processPaths = { if (running) listOf("/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm") else emptyList() },
            security = FakeSecurity { arguments ->
                if (keychain == null || "gemini" !in arguments || "antigravity" !in arguments) SecurityResult(44, "")
                else SecurityResult(0, "go-keyring-base64:" + Base64.getEncoder().encodeToString(keychain.toByteArray()))
            },
        )
        val definition = TestDefinitions.builtIn("antigravity")
        return Provider(
            definition = definition, settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, definition.id, null, TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    @Test
    fun `should keep Antigravity's name, on by default, with no dashboard and no account form`() {
        val provider = make()
        assertEquals("Antigravity", provider.name)
        assertTrue(provider.defaultAccount.isEnabled)
        assertNull(provider.plainDashboardURL)
        assertTrue(provider.accounts.form.isEmpty())
    }

    // The running app

    @Test
    fun `should show the running app's shared pools with their stated windows`() {
        val seen = Seen()
        val provider = make(answers = mapOf("RetrieveUserQuotaSummary" to (200 to """{"response":$summary}""")), seen = seen)
        val quotas = provider.refreshPlain().usage().quotas
        assertEquals(
            listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.ModelSpecific("Claude"), QuotaType.ModelSpecific("Claude Weekly")),
            quotas.map { it.quotaType },
        )
        assertEquals(listOf(80.0, 60.0, 40.0, 20.0), quotas.map { it.percentRemaining })
        // A 5-hour bucket is 5 hours — the probe called the 3p one a week.
        assertEquals(listOf(18000.0, 604800.0, 18000.0, 604800.0), quotas.map { it.window?.lengthSeconds })
        val request = seen.requests.first()
        assertEquals("https://127.0.0.1:42135/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary", request.url)
        assertEquals("9f808dbe-cb96-4829", request.header("X-Codeium-Csrf-Token"))
    }

    @Test
    fun `should show a quota per model with the plan and email when an older app answers`() {
        val snapshot = make(answers = mapOf("GetUserStatus" to (200 to userStatus))).refreshPlain().usage()
        assertEquals(listOf(QuotaType.ModelSpecific("Claude Sonnet"), QuotaType.ModelSpecific("Gemini Pro")), snapshot.quotas.map { it.quotaType })
        assertEquals(listOf(75.0, 50.0), snapshot.quotas.map { it.percentRemaining })
        assertEquals(1735689600.0, snapshot.quotas[1].resetsAtSeconds)
        assertEquals("user@example.com", snapshot.accountEmail)
        assertEquals(AccountTier.Custom("PRO"), snapshot.accountTier)
    }

    // The app closed: Google, with its saved login

    @Test
    fun `should show Google's quota with the saved login when the app is closed`() {
        val seen = Seen()
        val provider = make(
            running = false,
            answers = mapOf(
                "retrieveUserQuotaSummary" to (200 to summary),
                "loadCodeAssist" to (200 to """{"paidTier":{"name":"Ultra"}}"""),
            ),
            keychain = """{"token":{"access_token":"ya29.valid","refresh_token":"1//r","expiry":"2030-01-01T00:00:00Z"}}""",
            seen = seen,
        )
        val snapshot = provider.refreshPlain().usage()
        assertEquals(4, snapshot.quotas.size)
        assertEquals(AccountTier.Custom("ULTRA"), snapshot.accountTier)
        val first = seen.requests.first()
        assertEquals("daily-cloudcode-pa.googleapis.com", URI(first.url).host)
        assertEquals("Bearer ya29.valid", first.header("Authorization"))
    }

    @Test
    fun `should ask to sign in again when the saved login is refused`() {
        val provider = make(
            running = false, answers = mapOf("retrieveUserQuotaSummary" to (401 to "")),
            keychain = """{"token":{"access_token":"ya29.stale"}}""",
        )
        val outcome = provider.refreshPlain()
        assertTrue(outcome is RefreshOutcome.Failed, "$outcome")
        val error = (outcome as RefreshOutcome.Failed).error
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals("Sign in to Antigravity or run `agy` again.", (error as UsageError.SessionExpired).hint)
    }

    @Test
    fun `should be unavailable when the app is neither running nor signed in`() {
        assertFalse(make(running = false).isPlainAvailable())
    }

    @Test
    fun `should be available when the app is running without a saved login`() {
        assertTrue(make().isPlainAvailable())
    }
}
