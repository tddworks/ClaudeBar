package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.AnsweringTransport
import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DEDICATED_FOLDER
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.CredentialRefresh
import com.tddworks.claudebar.datasources.lookup.FakeCookies
import com.tddworks.claudebar.datasources.lookup.FakeDatabase
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.mapping.GraalScriptEngine
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test
import java.io.File
import java.net.URI
import java.time.Instant
import java.util.Collections

/**
 * Gemini as data: the Gemini CLI's login file, Code Assist's project, then its per-model quota
 * — the old probe's fixtures, quota for quota. A refused token runs `gemini` once to renew its
 * own login.
 */
class GeminiDefinitionTest {
    private val tiers = """{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-3-pro-preview","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-3.1-pro-preview","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-2.5-flash","remainingFraction":0.96,"resetTime":"2026-05-10T17:29:03Z"},{"modelId":"gemini-3-flash-preview","remainingFraction":0.96,"resetTime":"2026-05-10T17:29:03Z"},{"modelId":"gemini-2.5-flash-lite","remainingFraction":1.0,"resetTime":"2026-05-11T14:56:55Z"},{"modelId":"gemini-3.1-flash-lite-preview","remainingFraction":1.0,"resetTime":"2026-05-11T14:56:55Z"}]}"""

    private class Seen {
        val requests: MutableList<HttpCall> = Collections.synchronizedList(mutableListOf())
        val runs: MutableList<CLICall> = Collections.synchronizedList(mutableListOf())
        fun body(path: String): String? = requests.lastOrNull { URI(it.url).path.endsWith(path) }?.let { it.body?.decodeToString() ?: "" }
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** Answers by path: Code Assist's [project], else the [quota]; a token other than `fresh` is refused when [refuseStale] says so. */
    private fun make(
        token: String? = "fresh", quota: String = tiers, project: Pair<Int, String> = 200 to """{"cloudaicompanionProject":"gen-lang-client-1"}""",
        refuseStale: Boolean = false, located: Boolean = true, seen: Seen = Seen(),
    ): Pair<Provider, File> {
        val home = TestDefinitions.folder("gemini")
        val file = File(home, ".gemini/oauth_creds.json")
        file.parentFile.mkdirs()
        if (token != null) file.writeText("""{"access_token":"$token","refresh_token":"r","expiry_date":1}""")
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                seen.requests += call
                if (refuseStale && call.header("Authorization") != "Bearer fresh") return Response(401, body = ByteArray(0))
                if (URI(call.url).path.endsWith(":loadCodeAssist")) return Response(project.first, body = project.second.encodeToByteArray())
                return Response(200, body = quota.encodeToByteArray())
            }
        }
        val cli = FakeCLIExecutor(if (located) "/opt/homebrew/bin/gemini" else null) {
            file.writeText("""{"access_token":"fresh","refresh_token":"r"}""")
            CLIResult("")
        }
        val connections = DataSources(
            home = home.path, environment = { null }, network = network, loopback = network,
            makeCLIExecutor = { call -> seen.runs += call; cli }, makeCommandExecutor = { cli },
            transports = RPCTransportFactory { _, _, _, _ -> AnsweringTransport() }, directory = { DEDICATED_FOLDER },
            processEnvironment = { emptyMap() }, files = DiskFiles, processPaths = { emptyList() },
            security = FakeSecurity { SecurityResult(1, "") }, database = FakeDatabase { _, _ -> emptyList() },
            browserCookies = FakeCookies(), browserStorage = FakeStorage(), loginShell = null, cloudWatch = null, priceCatalog = null,
            scriptEngine = GraalScriptEngine(), now = { 1778420000.0 },
        )
        val definition = TestDefinitions.builtIn("gemini")
        val provider = Provider(
            definition = definition, settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, definition.id, null, TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), paths = HomePaths(home.path), isExecutable = { true }, locate = { it },
        )
        return provider to home
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should be Gemini, on by default, with AI Studio as its dashboard`() {
        val (provider, _) = make()
        assertEquals("Gemini", provider.name)
        assertTrue(provider.defaultAccount.isEnabled)
        assertEquals("https://aistudio.google.com", provider.plainDashboardURL)
    }

    @Test
    fun `should ask for the quota of the project Code Assist names, with the Gemini CLI's login`() {
        val seen = Seen()
        val (provider, _) = make(seen = seen)
        provider.refreshPlain()
        assertEquals("""{"metadata":{"pluginType":"GEMINI"}}""", seen.body(":loadCodeAssist"))
        assertEquals("""{"project":"gen-lang-client-1"}""", seen.body(":retrieveUserQuota"))
        assertTrue(seen.requests.all { it.header("Authorization") == "Bearer fresh" })
    }

    @Test
    fun `should still show the quotas when Code Assist names no project`() {
        val seen = Seen()
        val (provider, _) = make(project = 200 to "{}", seen = seen)
        assertEquals(3, provider.refreshPlain().usage().quotas.size)
        assertEquals("{}", seen.body(":retrieveUserQuota"))
    }

    @Test
    fun `should show the quotas without a project after Code Assist fails three times to name one`() {
        val seen = Seen()
        val (provider, _) = make(project = 500 to "", seen = seen)
        assertEquals(3, provider.refreshPlain().usage().quotas.size)
        assertEquals(3, seen.requests.count { URI(it.url).path.endsWith(":loadCodeAssist") })
        assertEquals("{}", seen.body(":retrieveUserQuota"))
    }

    @Test
    fun `should show one Pro, Flash and Flash Lite quota each at its lowest model, with no guessed window`() {
        val (provider, _) = make()
        val quotas = provider.refreshPlain().usage().quotas
        assertEquals(
            listOf(QuotaType.ModelSpecific("Pro"), QuotaType.ModelSpecific("Flash"), QuotaType.ModelSpecific("Flash Lite")),
            quotas.map { it.quotaType },
        )
        assertEquals(listOf(88.0, 96.0, 100.0), quotas.map { it.percentRemaining })
        // The response states no window, so none is guessed.
        assertTrue(quotas.all { it.window?.lengthSeconds == null })
    }

    @Test
    fun `should show a model outside the known tiers under its own name`() {
        val (provider, _) = make(quota = """{"buckets":[{"modelId":"gemini-other","remainingFraction":0.5}]}""")
        assertEquals(QuotaType.ModelSpecific("gemini-other"), provider.refreshPlain().usage().quotas.firstOrNull()?.quotaType)
    }

    @Test
    fun `should show when a quota resets as a moment and a countdown`() {
        val (provider, _) = make()
        val pro = provider.refreshPlain().usage().quotas.firstOrNull()
        assertNotNull(pro)
        assertEquals(Instant.parse("2026-05-10T17:28:41Z").epochSecond.toDouble(), pro!!.resetsAtSeconds)
        assertEquals("Resets in 3h 55m", pro.resetText)
    }

    @Test
    fun `should fail when Gemini reports no quotas`() {
        val (provider, _) = make(quota = """{"buckets":[]}""")
        assertEquals(UsageError.ParseFailed("No quota buckets in response"), provider.refreshPlain().failure())
    }

    @Test
    fun `should be unavailable when the Gemini CLI has no login on this Mac`() {
        val (provider, _) = make(token = null)
        assertFalse(provider.isPlainAvailable())
    }

    @Test
    fun `should renew a refused login by running the Gemini CLI, then show the quotas`() {
        val seen = Seen()
        val (provider, home) = make(token = "stale", refuseStale = true, seen = seen)
        assertEquals(3, provider.refreshPlain().usage().quotas.size)
        val run = seen.runs.firstOrNull { it.cli == "gemini" && it.input == "/quit\n" }
        assertNotNull(run)
        assertTrue(run!!.environment.unset.contains("GEMINI_API_KEY"))
        // Gemini's own file: ClaudeBar never writes it.
        assertEquals("""{"access_token":"fresh","refresh_token":"r"}""", File(home, ".gemini/oauth_creds.json").readText())
    }

    @Test
    fun `should ask to sign in again when the login is refused and the Gemini CLI isn't installed`() {
        val (provider, _) = make(token = "stale", refuseStale = true, located = false)
        assertEquals(UsageError.AuthenticationRequired, provider.refreshPlain().failure())
    }

    @Test
    fun `should read an added login from its own Gemini home, renewed by the Gemini CLI there`() {
        val (provider, _) = make()
        assertEquals(listOf("home"), provider.accounts.form.map { it.id })
        val definition = TestDefinitions.builtIn("gemini")
        val source = definition.dataSourcesForAccount(mapOf("home" to "/Users/me/gemini-work")).firstOrNull()
        assertNotNull(source)
        val credential = source!!.credential
        val base = (credential as? CredentialLookup.Refreshing)?.base as? CredentialLookup.JsonFile
        val refresh = (credential as? CredentialLookup.Refreshing)?.refresh as? CredentialRefresh.Cli
        if (base == null || refresh == null) fail<Unit>("Expected Gemini's login file renewed by its CLI, got $credential")
        assertEquals(PathPattern("/Users/me/gemini-work/.gemini/oauth_creds.json"), base!!.file.path)
        assertEquals("/Users/me/gemini-work", refresh!!.call.environment.set["GEMINI_CLI_HOME"])
        assertEquals(listOf("/Users/me/gemini-work/.gemini/oauth_creds.json"), source.requiresFiles)
    }
}
