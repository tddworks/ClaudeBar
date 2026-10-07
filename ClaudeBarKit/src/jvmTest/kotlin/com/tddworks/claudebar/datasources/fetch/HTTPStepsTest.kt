package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.HTTPStatusError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import io.ktor.http.Url
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource

/** `"http": { "steps": […] }` — call A, then B with something A said. */
class HTTPStepsTest {
    private val now = 1_700_000_000.0

    /** Answers by path, keeping what was sent in order. */
    internal class ByPath(private val answer: (path: String, times: Int) -> Pair<Int, String>?) : NetworkClient {
        val sent = mutableListOf<HttpCall>()
        override suspend fun send(call: HttpCall): Response {
            sent += call
            val path = Url(call.url).encodedPath
            val (status, body) = answer(path, times(path)) ?: (404 to "")
            return Response(status, body = body.encodeToByteArray())
        }

        val paths get() = sent.map { Url(it.url).encodedPath }
        fun times(path: String) = paths.count { it == path }
        private fun last(path: String) = sent.last { Url(it.url).encodedPath == path }
        fun header(name: String, path: String) = last(path).headers.entries.firstOrNull { it.key.equals(name, true) }?.value
        fun query(name: String, path: String) = Url(last(path).url).parameters[name]
        fun body(path: String) = last(path).body?.decodeToString()
    }

    private fun network(answers: Map<String, Pair<Int, String>>) = ByPath { path, _ -> answers[path] }

    private fun steps(json: String) = Fetch.from(Json.parseToJsonElement("""{"http":$json}""")) as Fetch.HttpSteps

    private fun fetcher(json: String, network: NetworkClient) = HTTPStepsFetcher(steps(json).steps, network) { now }

    private fun answers(response: Response) = Json.parseToJsonElement(response.text) as JsonObject

    private fun used(response: Response, step: String) = answers(response)[step]!!.jsonObject["used"]!!.jsonPrimitive.int

    private suspend fun failure(block: suspend () -> Unit): Exception? = try {
        block()
        null
    } catch (error: Exception) {
        error
    }

    private val twoSteps = """
    {"steps":[
       {"name":"project","request":{"url":"https://acme.test/project","headers":{"Authorization":"Bearer {{token}}"}},
        "keep":{"project":"$.project.id"}},
       {"name":"usage","request":{"url":"https://acme.test/usage/{{project}}"}}]}
    """

    private val key = Credential(mapOf("token" to "k"))

    @Test
    fun `should show the quota from a second request that uses what the first one learned`() = runTest {
        val network = network(mapOf("/project" to (200 to """{"project":{"id":"p-7"}}"""), "/usage/p-7" to (200 to """{"used":40}""")))

        val response = fetcher(twoSteps, network).fetch(key)

        assertEquals(40, used(response, "usage"))
        assertEquals(listOf("/project", "/usage/p-7"), network.paths)
    }

    @Test
    fun `should show every step's answer by its name when the connection is tested`() = runTest {
        val network = network(mapOf("/project" to (200 to """{"project":{"id":"p-7"}}"""), "/usage/p-7" to (200 to """{"used":40}""")))

        val response = fetcher(twoSteps, network).fetch(key)
        val answers = answers(response)

        assertNotNull(answers["project"]!!.jsonObject["project"])
        assertEquals(40, used(response, "usage"))
        assertEquals(200, response.status)
    }

    @Test
    fun `should use a value from the next place the answer holds it when the first is empty`() = runTest {
        val network = network(mapOf("/who" to (200 to """{"org":{"id":42}}"""), "/usage" to (200 to """{"used":5}""")))

        fetcher(
            """{"steps":[
               {"name":"who","request":{"url":"https://acme.test/who"},"keep":{"org":["$.data.org.id","$.org.id"]}},
               {"name":"usage","request":{"url":"https://acme.test/usage?org={{org}}"}}]}""",
            network,
        ).fetch(null)

        assertEquals("42", network.query("org", "/usage"))
    }

    @Test
    fun `should leave a value the earlier step didn't find out of the URL`() = runTest {
        val network = network(mapOf("/who" to (200 to "{}"), "/usage" to (200 to """{"used":5}""")))

        fetcher(
            """{"steps":[
               {"name":"who","request":{"url":"https://acme.test/who"},"keep":{"org":"$.org.id"}},
               {"name":"usage","request":{"url":"https://acme.test/usage?org={{org}}&v=1"},"dropEmpty":["org"]}]}""",
            network,
        ).fetch(null)

        assertNull(network.query("org", "/usage"))
        assertEquals("1", network.query("v", "/usage"))
    }

    @Test
    fun `should send no header for a value that wasn't found`() = runTest {
        val network = network(mapOf("/usage" to (200 to """{"used":5}""")))

        fetcher(
            """{"steps":[
               {"name":"usage","request":{"url":"https://acme.test/usage","headers":{"x-csrf-token":"{{csrf}}","Accept":"*/*"}},
                "dropEmpty":["csrf"]}]}""",
            network,
        ).fetch(null)

        assertNull(network.header("x-csrf-token", "/usage"))
        assertEquals("*/*", network.header("Accept", "/usage"))
    }

    @Test
    fun `should always send the person's own key, never one a server answered with`() = runTest {
        val network = network(mapOf("/a" to (200 to """{"token":"stolen"}"""), "/b" to (200 to """{"used":1}""")))

        fetcher(
            """{"steps":[
               {"name":"a","request":{"url":"https://acme.test/a"},"keep":{"token":"$.token"}},
               {"name":"b","request":{"url":"https://acme.test/b","headers":{"Authorization":"Bearer {{token}}"}}}]}""",
            network,
        ).fetch(Credential(mapOf("token" to "mine")))

        assertEquals("Bearer mine", network.header("Authorization", "/b"))
    }

    @Test
    fun `should still show the quota when an optional step fails, without its value`() = runTest {
        val network = network(mapOf("/project" to (500 to ""), "/usage" to (200 to """{"used":10}""")))

        val response = fetcher(
            """{"steps":[
               {"name":"project","request":{"url":"https://acme.test/project"},"optional":true,"keep":{"project":"$.id"}},
               {"name":"usage","request":{"url":"https://acme.test/usage","method":"POST","body":"{\"project\":\"{{project}}\"}"},
                "dropEmpty":["project"]}]}""",
            network,
        ).fetch(null)

        assertEquals(10, used(response, "usage"))
        assertEquals("{}", network.body("/usage"))
    }

    @ParameterizedTest
    @CsvSource("401, authenticationRequired", "429, rateLimited")
    fun `should still ask to sign in or wait when an optional step is refused or rate limited`(status: Int, tag: String) = runTest {
        val network = network(mapOf("/project" to (status to ""), "/usage" to (200 to """{"used":10}""")))
        val fetcher = fetcher(
            """{"steps":[
               {"name":"project","request":{"url":"https://acme.test/project"},"optional":true},
               {"name":"usage","request":{"url":"https://acme.test/usage"}}]}""",
            network,
        )

        val error = failure { fetcher.fetch(null) } as? HTTPStatusError

        assertEquals(tag, error?.reason?.tag)
    }

    @Test
    fun `should skip a step whose value is already known`() = runTest {
        val network = network(mapOf("/usage" to (200 to """{"used":5}""")))

        fetcher(
            """{"steps":[
               {"name":"token","request":{"url":"https://acme.test/token"},"unless":"token","keep":{"token":"$.t"}},
               {"name":"usage","request":{"url":"https://acme.test/usage"}}]}""",
            network,
        ).fetch(Credential(mapOf("token" to "known")))

        assertEquals(listOf("/usage"), network.paths)
    }

    @Test
    fun `should pick a value out of a page's text by its pattern for the next step`() = runTest {
        val network = network(mapOf("/page" to (200 to """<meta csrf="ab12">"""), "/usage" to (200 to """{"used":5}""")))

        fetcher(
            """{"steps":[
               {"name":"page","request":{"url":"https://acme.test/page"},"keep":{"csrf":{"pattern":"csrf=\"([a-z0-9]+)\""}}},
               {"name":"usage","request":{"url":"https://acme.test/usage","headers":{"X-CSRF":"{{csrf}}"}}}]}""",
            network,
        ).fetch(null)

        assertEquals("ab12", network.header("X-CSRF", "/usage"))
    }

    @Test
    fun `should try a step again after a server error when the definition allows attempts`() = runTest {
        val network = ByPath { _, times -> (if (times == 1) 503 else 200) to """{"used":20}""" }

        val response = fetcher(
            """{"steps":[{"name":"usage","request":{"url":"https://acme.test/usage"},"attempts":2}]}""",
            network,
        ).fetch(null)

        assertEquals(20, used(response, "usage"))
        assertEquals(2, network.times("/usage"))
    }

    @Test
    fun `should fail at fetching when a required step fails`() = runTest {
        val fetcher = fetcher(twoSteps, network(mapOf("/project" to (500 to ""))))

        val error = failure { fetcher.fetch(key) } as? HTTPStatusError

        assertEquals(500, error?.status)
        assertEquals(UsageError.ExecutionFailed("HTTP error: 500"), error?.reason)
    }

    @ParameterizedTest
    @ValueSource(
        strings = [
            """{"steps":[]}""",
            """{"steps":[{"name":"a","request":{"url":"u"}},{"name":"a","request":{"url":"u"}}]}""",
            """{"steps":[{"name":"a","request":{"url":"u"},"attempts":9}]}""",
        ],
    )
    fun `should reject steps that are empty, share a name or try too many times`(http: String) {
        assertThrows<DefinitionError> { steps(http) }
    }

    @Test
    fun `should keep multi-step requests when the definition is written out and read back`() {
        val fetch = steps(twoSteps)
        assertEquals(fetch, Fetch.from(fetch.toJson()))
    }
}
