package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.BrowserCookie
import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DEDICATED_FOLDER
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.datasources.lookup.FakeDatabase
import com.tddworks.claudebar.datasources.lookup.FakeSecurity
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.datasources.mapping.GraalScriptEngine
import com.tddworks.claudebar.datasources.process.DiskFiles
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.process.RPCTransportFactory
import com.tddworks.claudebar.datasources.AnsweringTransport
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.net.URI
import java.util.Collections
import java.util.TimeZone
import java.util.UUID

/**
 * Kimi on stubbed connections: the CLI types /usage into `kimi`; the API reads the web session
 * for the chosen region. An added login brings what the active data source needs — a session
 * token, or a signed-in folder.
 */
class KimiExecutionTest {
    private val api = """{"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"2048","used":"214","remaining":"1834","resetTime":"2025-06-09T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"139","remaining":"61","resetTime":"2025-06-03T15:30:00Z"}}]}]}"""
    private val screen = """
      ╭ Usage ───────────────────────────────────────────────────────────╮
      │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
      │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
      ╰──────────────────────────────────────────────────────────────────╯
    """.trimIndent().prependIndent("  ")

    private class Seen {
        @Volatile var host: String? = null
        @Volatile var cookie: String? = null
        @Volatile var origin: String? = null
        val calls: MutableList<CLICall> = Collections.synchronizedList(mutableListOf())
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** Kimi with its old card's settings where it kept them: `kimi.region` and `kimi.probeMode`. */
    private fun make(
        region: String? = null, mode: String? = null, status: Int = 200, vault: MemoryVault = MemoryVault(),
        cookies: Map<String, String> = emptyMap(), environment: Map<String, String> = emptyMap(), seen: Seen = Seen(),
    ): Provider {
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                val uri = URI(call.url)
                seen.host = uri.host
                seen.cookie = call.header("Cookie")
                seen.origin = call.header("Origin")
                if (call.method != "POST" || uri.path != "/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages" ||
                    call.body?.decodeToString() != """{"scope":["FEATURE_CODING"]}""" ||
                    call.header("r-timezone") != TimeZone.getDefault().id
                ) {
                    return Response(400, body = ByteArray(0))
                }
                return Response(status, body = api.encodeToByteArray())
            }
        }
        val browser = object : BrowserCookieReading {
            override fun stores(domains: List<String>, names: List<String>): List<List<BrowserCookie>> =
                if (names != listOf("kimi-auth")) emptyList() else domains.mapNotNull { cookies[it] }.map { listOf(BrowserCookie("kimi-auth", it)) }
        }
        val cli = FakeCLIExecutor("/opt/homebrew/bin/kimi") { CLIResult(screen) }
        val settings = InMemoryProviderSettings()
        settings.setValue(region, "region", "kimi")
        if (mode != null) settings.setDataSourceKind(mode, "kimi")
        val definition = TestDefinitions.builtIn("kimi")
        val connections = DataSources(
            home = TEMP_HOME, environment = { environment[it] }, network = network, loopback = network,
            makeCLIExecutor = { call -> seen.calls += call; cli }, makeCommandExecutor = { cli },
            transports = RPCTransportFactory { _, _, _, _ -> AnsweringTransport() }, directory = { DEDICATED_FOLDER },
            processEnvironment = { environment }, files = DiskFiles, processPaths = { emptyList() },
            security = FakeSecurity { SecurityResult(1, "") }, database = FakeDatabase { _, _ -> emptyList() },
            browserCookies = browser, browserStorage = FakeStorage(), loginShell = null, cloudWatch = null, priceCatalog = null,
            scriptEngine = GraalScriptEngine(), now = { System.currentTimeMillis() / 1000.0 },
        )
        return Provider(
            definition = definition, settings = settings, saved = settings.accounts("kimi"),
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    // CLI, the default

    @Test
    fun `should ask kimi for -usage once its screen settles when no data source is chosen`() {
        val seen = Seen()
        val quotas = make(seen = seen).refreshPlain().usage().quotas
        assertEquals(listOf(QuotaType.Weekly, QuotaType.Session), quotas.map { it.quotaType })
        assertEquals(listOf(10.0, 88.0), quotas.map { it.percentRemaining })
        val call = seen.calls.first()
        assertEquals("/usage", call.input)
        assertEquals(1.5, call.inputDelay)
        assertEquals(WorkingDirectory.DEDICATED, call.workingDirectory)
        assertEquals("/usage\r", call.autoResponses["context:"])
    }

    @Test
    fun `should read usage from the web when the old card chose the API`() {
        val seen = Seen()
        make(mode = "api", cookies = mapOf("kimi.com" to "browser"), seen = seen).refreshPlain()
        assertEquals("www.kimi.com", seen.host)
        assertEquals("kimi-auth=browser", seen.cookie)
    }

    // API

    @Test
    fun `should show the Moderato plan's weekly quota and its 5-hour limit when read from the web`() {
        val snapshot = make(mode = "api", cookies = mapOf("kimi.com" to "browser")).refreshPlain().usage()
        val weekly = snapshot.quota(QuotaType.Weekly)
        assertNotNull(weekly)
        assertEquals(604800.0, weekly!!.window?.lengthSeconds)
        assertEquals("214/2048 requests", weekly.resetText)
        val session = snapshot.quota(QuotaType.Session)
        assertNotNull(session)
        assertEquals(30.5, session!!.percentRemaining)
        assertEquals(18000.0, session.window?.lengthSeconds)
        assertEquals(AccountTier.Custom("Moderato"), snapshot.accountTier)
    }

    @Test
    fun `should use kimi_ai and its own browser session when the region is international`() {
        val seen = Seen()
        val provider = make(region = "international", mode = "api", cookies = mapOf("kimi.com" to "china", "kimi.ai" to "international"), seen = seen)
        provider.refreshPlain()
        assertEquals("www.kimi.ai", seen.host)
        assertEquals("https://www.kimi.ai", seen.origin)
        assertEquals("kimi-auth=international", seen.cookie)
        assertEquals("https://www.kimi.ai/code/console", provider.plainDashboardURL)
    }

    @Test
    fun `should use KIMI_AUTH_TOKEN over the browser session when both are set`() {
        val seen = Seen()
        make(mode = "api", cookies = mapOf("kimi.com" to "browser"), environment = mapOf("KIMI_AUTH_TOKEN" to "env"), seen = seen).refreshPlain()
        assertEquals("kimi-auth=env", seen.cookie)
    }

    @Test
    fun `should be unavailable when there is no web session anywhere`() {
        val product = make(mode = "api")
        val account = product.defaultAccount
        assertFalse(runBlocking { product.isAvailable(account) })
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when Kimi refuses the session`(code: Int) {
        assertEquals(UsageError.AuthenticationRequired, make(mode = "api", status = code, cookies = mapOf("kimi.com" to "browser")).refreshPlain().failure())
    }

    @Test
    fun `should open the China dashboard when no region is saved`() {
        assertEquals("https://www.kimi.com/code/console", make().plainDashboardURL)
    }

    // Added accounts

    @Test
    fun `should ask for a session token and a region when adding a login on the API`() {
        assertEquals(listOf("token", "region"), make(mode = "api").accounts.form.map { it.id })
    }

    @Test
    fun `should ask for a signed-in folder and a region when adding a login on the CLI`() {
        assertEquals(listOf("home", "region"), make().accounts.form.map { it.id })
    }

    @Test
    fun `should use an added login's own token and region, never the browser, on the API`() {
        val seen = Seen()
        val vault = MemoryVault()
        val provider = make(mode = "api", vault = vault, cookies = mapOf("kimi.com" to "browser"), environment = mapOf("KIMI_AUTH_TOKEN" to "env"), seen = seen)
        val work = provider.accounts.add(mapOf("token" to "work", "region" to "international")).done()
        provider.refreshNow(work)
        assertEquals("kimi-auth=work", seen.cookie)
        assertEquals("www.kimi.ai", seen.host)
    }

    @Test
    fun `should run kimi in an added login's own folder on the CLI`() {
        val seen = Seen()
        // Written one way (symlinks resolved), as the JVM reads it back.
        val folder = File(File(TEMP_HOME).canonicalFile, UUID.randomUUID().toString()).apply { mkdirs() }
        try {
            val provider = make(seen = seen)
            val work = provider.accounts.add(mapOf("home" to folder.path)).done()
            provider.refreshNow(work)
            val call = seen.calls.last()
            assertEquals(folder.path, call.environment.set["KIMI_SHARE_DIR"])
            assertEquals(folder.path, call.environment.set["KIMI_CODE_HOME"])
            assertTrue(call.environment.unset.contains("KIMI_AUTH_TOKEN"))
        } finally {
            folder.deleteRecursively()
        }
    }
}

/** A login added for one data source runs only the sources it has values for. */
class SourceScopedAccountTest {
    private fun definition(): ProviderDefinition = TestDefinitions.builtIn("kimi")

    @Test
    fun `should read only the web when a login has no folder`() {
        val sources = definition().dataSourcesForAccount(mapOf("region" to "china"))
        assertEquals(listOf("api"), sources.map { it.kind })
    }

    @Test
    fun `should read both the CLI and the web when a login has a folder`() {
        val sources = definition().dataSourcesForAccount(mapOf("region" to "china", "home" to "/tmp/kimi-work"))
        assertEquals(listOf("cli", "api"), sources.map { it.kind })
    }
}
