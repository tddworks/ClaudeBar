package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Instant

/** Cline as data: the plan's five-hour, weekly and monthly limits from `api.cline.bot`, with a pasted key or the login `cline auth` saved. */
class ClineDefinitionTest {
    private val limits = """
        {"success":true,"data":{"limits":[
         {"type":"five_hour","percentUsed":12.5,"resetsAt":"2026-07-16T15:00:00Z"},
         {"type":"experimental_pool","percentUsed":77,"resetsAt":"2026-07-16T15:00:00Z"},
         {"type":"weekly","percentUsed":25,"resetsAt":"2026-07-20T00:00:00Z"},
         {"type":"monthly","percentUsed":40,"resetsAt":null}]}}
    """.trimIndent()

    /** The Authorization header of the last request. */
    private class Seen {
        @Volatile var last: String? = null
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** A Cline login file under a fresh home folder, written as `cline auth` saves it. */
    private fun home(settings: JsonObject? = null): File {
        val root = TestDefinitions.folder("cline")
        val folder = File(root, ".cline/data/settings").apply { mkdirs() }
        if (settings != null) {
            val file = JsonObject(mapOf("providers" to JsonObject(mapOf("cline" to JsonObject(mapOf("settings" to settings))))))
            File(folder, "providers.json").writeText(file.toString())
        }
        return root
    }

    private fun obj(vararg pairs: Pair<String, Any>): JsonObject = JsonObject(
        pairs.associate { (key, value) -> key to (if (value is JsonObject) value else JsonPrimitive(value as String)) },
    )

    private fun make(
        body: String = limits, status: Int = 200, home: File? = null, environment: Map<String, String> = emptyMap(),
        vault: MemoryVault = MemoryVault(), seen: Seen = Seen(),
    ): Provider {
        val definition = TestDefinitions.builtIn("cline")
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                if (call.url != "https://api.cline.bot/api/v1/users/me/plan/usage-limits" || call.method != "GET" ||
                    call.header("Accept") != "application/json"
                ) {
                    return Response(400, body = ByteArray(0))
                }
                seen.last = call.header("Authorization")
                return Response(status, body = body.encodeToByteArray())
            }
        }
        val folder = (home ?: home()).path
        val connections = testDataSources(network = network, environment = environment, home = folder)
        return Provider(
            definition = definition, settings = InMemoryProviderSettings(),
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(folder), isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    private fun seconds(iso: String) = Instant.parse(iso).epochSecond.toDouble()

    @Test
    fun `should be Cline, off until turned on, with its dashboard and icon`() {
        val cline = make()
        assertEquals("cline", cline.id)
        assertEquals("Cline", cline.name)
        assertEquals(false, cline.plainIsInLineup)
        assertEquals("https://app.cline.bot/dashboard", cline.definition.profile.links.dashboard)
        assertEquals("ClineIcon", cline.definition.profile.look.icon)
    }

    @Test
    fun `should show the five-hour, weekly and monthly limits and skip a limit it doesn't know`() {
        val usage = make(environment = mapOf("CLINE_API_KEY" to "key")).refreshPlain().usage()

        assertEquals(3, usage.quotas.size)
        val session = usage.quota(QuotaType.Session)
        assertNotNull(session)
        assertEquals(87.5, session!!.percentRemaining)
        assertEquals(seconds("2026-07-16T15:00:00Z"), session.resetsAtSeconds)
        assertEquals(75.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(seconds("2026-07-20T00:00:00Z"), usage.quota(QuotaType.Weekly)?.resetsAtSeconds)
        val monthly = usage.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Monthly") }
        assertNotNull(monthly)
        assertEquals(60.0, monthly!!.percentRemaining)
        assertNull(monthly.resetsAtSeconds)
    }

    @Test
    fun `should send a pasted key as it is`() {
        val seen = Seen()
        make(vault = MemoryVault(mapOf("cline.apiKey" to "pasted")), seen = seen).refreshPlain()
        assertEquals("Bearer pasted", seen.last)
    }

    @Test
    fun `should use the login cline auth saved, marked as a WorkOS token`() {
        val seen = Seen()
        make(home = home(obj("auth" to obj("accessToken" to "session-token"))), seen = seen).refreshPlain()
        assertEquals("Bearer workos:session-token", seen.last)
    }

    @Test
    fun `should not mark a saved login twice when it is already a WorkOS token`() {
        val seen = Seen()
        make(home = home(obj("auth" to obj("accessToken" to "workos:session-token"))), seen = seen).refreshPlain()
        assertEquals("Bearer workos:session-token", seen.last)
    }

    @Test
    fun `should use the API key saved in Cline's settings when it has no login`() {
        val seen = Seen()
        make(home = home(obj("apiKey" to "settings-key")), seen = seen).refreshPlain()
        assertEquals("Bearer settings-key", seen.last)
    }

    @Test
    fun `should prefer the environment key over Cline's own login`() {
        val seen = Seen()
        make(home = home(obj("auth" to obj("accessToken" to "session-token"))), environment = mapOf("CLINE_API_KEY" to "environment"), seen = seen).refreshPlain()
        assertEquals("Bearer environment", seen.last)
    }

    @Test
    fun `should ask for a key when there is neither a key nor a Cline login`() {
        val cline = make()
        val account = cline.defaultAccount
        assertEquals(UsageError.AuthenticationRequired, cline.refreshNow(account).failure())
        assertEquals(DataSourceError.Step.LOOKUP, account.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when Cline refuses the key`(status: Int) {
        val cline = make(status = status, environment = mapOf("CLINE_API_KEY" to "key"))
        val error = cline.refreshNow(cline.defaultAccount).failure()
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals("Run `cline auth` or paste a new API key.", (error as UsageError.SessionExpired).hint)
    }

    @ParameterizedTest
    @ValueSource(strings = ["""{"success":false}""", """{"success":true,"data":{"limits":[]}}"""])
    fun `should fail reading the limits when Cline lists none`(body: String) {
        val cline = make(body = body, environment = mapOf("CLINE_API_KEY" to "key"))
        val account = cline.defaultAccount
        cline.refreshNow(account).failure()
        assertEquals(DataSourceError.Step.MAPPING, account.lastFailedStep)
    }
}
