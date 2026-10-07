package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class DataSourceTest {
    private fun make(
        definition: DataSourceDefinition,
        network: NetworkClient = AnsweringNetwork(),
        environment: Map<String, String> = emptyMap(),
    ): DataSource = testDataSources(network = network, environment = environment).make(definition, "test")

    private fun http(body: String, status: Int = 200, headers: Map<String, String> = emptyMap()) =
        AnsweringNetwork.answering(body, status, headers)

    // Definitions as JSON

    @Test
    fun `should read a definition's key, fetch and mapping by their names, shown and with no fallback by default`() {
        val definition = definition("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"url":"https://example.com/usage"}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """)

        assertEquals(CredentialLookup.Environment("KEY"), definition.credential)
        assertEquals(Fetch.Http(HTTPRequest(url = "https://example.com/usage")), definition.fetch)
        assertFalse(definition.hidden)
        assertNull(definition.fallback)
    }

    @Test
    fun `should reject a definition whose fetch names two ways at once`() {
        assertThrows<DefinitionError> {
            definition("""{"kind":"x","fetch":{"http":{"url":"u"},"cli":{"cli":"c"}},"mapping":{"json":{"quotas":[]}}}""")
        }
    }

    // Fetching usage

    @Test
    fun `should show the quota when the environment's API key is sent where the definition places it`() = runTest {
        val network = AnsweringNetwork { call ->
            if (call.headers["Authorization"] == "Bearer sk-1") Response(200, body = """{"used":25}""".encodeToByteArray())
            else Response(401, body = ByteArray(0))
        }
        val source = make(definition("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"url":"https://example.com","headers":{"Authorization":"Bearer {{token}}"}}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """), network, mapOf("KEY" to "sk-1"))

        val usage = source.fetchUsage()

        assertEquals(75.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should show the raw status, headers and body when the connection is tested`() = runTest {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"nowhere"}]}}}
        """), http("""{"data":{"limit":50}}""", headers = mapOf("X-Thing" to "1")))

        val response = source.fetchResponse()

        assertEquals(200, response.status)
        assertEquals("1", response.header("x-thing"))
        assertEquals("""{"data":{"limit":50}}""", response.text)
    }

    @Test
    fun `should not be ready, and fail at finding the key, when there is no key`() = runTest {
        val source = make(definition("""
        {"kind":"api","credential":{"environment":"KEY"},"fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[]}}}
        """))

        assertFalse(source.isReady())
        assertEquals(DataSourceError(DataSourceError.Step.LOOKUP, UsageError.AuthenticationRequired), thrown { source.fetchUsage() })
    }

    @Test
    fun `should fail at fetching, naming the HTTP status, when the server errors`() = runTest {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), http("", status = 500))

        assertEquals(DataSourceError(DataSourceError.Step.FETCH, UsageError.ExecutionFailed("HTTP error: 500")), thrown { source.fetchUsage() })
    }

    @Test
    fun `should say when to try again when the server is rate limited`() = runTest {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), http("", status = 429, headers = mapOf("Retry-After" to "120")))

        assertEquals(DataSourceError(DataSourceError.Step.FETCH, UsageError.RateLimited(1_700_000_120.0)), thrown { source.fetchUsage() })
    }

    @Test
    fun `should fail at reading the answer when the server doesn't answer in JSON`() = runTest {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), http("<html>"))

        assertEquals(DataSourceError(DataSourceError.Step.MAPPING, UsageError.ParseFailed("Response is not JSON")), thrown { source.fetchUsage() })
    }

    // Mapping

    @Test
    fun `should show a credit balance as money left with a budget and no reset`() {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"model","name":"Credits","at":"$.data","leftPercent":"left"}],
                            "cost":{"used":"$.data.usage","limit":"$.data.limit"}}}}
        """))

        val usage = source.read(Response("""{"data":{"left":24.8,"usage":37.6,"limit":50}}"""))

        assertEquals(24.8, usage.quota(QuotaType.ModelSpecific("Credits"))?.percentRemaining)
        assertNull(usage.quota(QuotaType.ModelSpecific("Credits"))?.resetsAtSeconds)
        assertEquals(50_000_000_000L, usage.costUsage?.budgetNanos)
    }

    @Test
    fun `should name each repeated quota from the answer, tidied, and skip one with no name`() {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"time","each":"$.limits",
           "name":{"firstOf":["name"],"dropPrefixes":[{"prefix":"codex_","capitalize":true}]},
           "usedPercent":"used"}]}}}
        """))

        val usage = source.read(Response("""{"limits":[{"name":"codex_spark","used":40},{"name":"","used":1}]}"""))

        assertEquals(listOf<QuotaType>(QuotaType.TimeLimit("Spark")), usage.quotas.map { it.quotaType })
        assertEquals(60.0, usage.quotas.first().percentRemaining)
    }

    @Test
    fun `should show when a quota resets as a countdown when the answer gives seconds from now`() {
        val source = make(definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"session","usedPercent":"used","resetsAt":{"secondsFromNow":"in"}}]}}}
        """))

        val quota = source.read(Response("""{"used":10,"in":5400}""")).quota(QuotaType.Session)

        assertEquals(1_700_005_400.0, quota?.resetsAtSeconds)
        assertEquals("Resets in 1h 30m", quota?.resetText)
    }

    @Test
    fun `should ask to sign in when the CLI screen says to log in, even beside its numbers`() {
        val source = make(definition("""
        {"kind":"cli","fetch":{"cli":{"cli":"tool"}},
         "mapping":{"text":{"errors":[{"contains":["please log in"],"error":"authenticationRequired"}],
                            "quotas":[{"kind":"session","label":"5h limit","leftPercent":"([0-9]+)% left"}]}}}
        """))

        val failure = assertThrows<DataSourceError> { source.read(Response("5h limit 80% left\nPlease log in")) }

        assertEquals(DataSourceError(DataSourceError.Step.MAPPING, UsageError.AuthenticationRequired), failure)
    }

    // Where a CLI runs

    @Test
    fun `should start a JSON-RPC CLI in ClaudeBar's own trusted folder (#267)`() = runTest {
        // Codex 0.150+ trust-checks the directory it starts in (#267), so the
        // app-server must start in ClaudeBar's own probe directory.
        var started: Triple<String, List<String>, String?>? = null
        val transport = AnsweringTransport()
        val sources = testDataSources(
            transports = { executable, arguments, _, directory ->
                started = Triple(executable, arguments, directory)
                transport
            },
        )
        val source = sources.make(definition("""
        {"kind":"rpc","fetch":{"jsonRpc":{"cli":"codex","args":["app-server"],"workingDirectory":"dedicated","call":"read"}},
         "mapping":{"json":{"quotas":[]}}}
        """), "test")

        source.fetchResponse()

        assertEquals("codex", started?.first)
        assertEquals(listOf("app-server"), started?.second)
        assertEquals(DEDICATED_FOLDER, started?.third)
    }

    // The path dialect

    @Test
    fun `should find a value from the answer's root, the current item, a response header or the item's key`() {
        val root = Json.parseToJsonElement("""{"a":{"b":2,"list":[{"c":3}]}}""")
        val scope = JsonScope(root, headers = mapOf("x-used" to "7"))
        val inner = scope.moved(scope.value("$.a"), key = "k")

        assertEquals(2.0, scope.number("$.a.b"))
        assertEquals(3.0, scope.number("$.a.list.0.c"))
        assertEquals(7.0, scope.number("\$header.X-Used"))
        assertEquals(2.0, inner.number("b"))
        assertEquals("k", inner.string("\$key"))
        assertNull(scope.moved(null).value("b"))
    }

    @Test
    fun `should leave a template's text out when its placeholder has no value`() {
        assertEquals("Bearer t", Template.fill("Bearer {{token}}", Credential(mapOf("token" to "t"))))
        assertNull(Template.fill("{{account}}", Credential(mapOf("token" to "t"))))
        assertEquals("plain", Template.fill("plain", null))
    }
}
