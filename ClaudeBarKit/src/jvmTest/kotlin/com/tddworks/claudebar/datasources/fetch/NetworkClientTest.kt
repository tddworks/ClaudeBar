package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.engine.mock.toByteArray
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The network adapters: what goes out is what the definition said, and any status is an answer. */
class NetworkClientTest {
    private val seen = mutableListOf<HttpRequestData>()
    private val bodies = mutableListOf<String>()

    private fun client(status: Int = 200, headers: Map<String, String> = emptyMap(), body: String = "{}") =
        KtorNetworkClient.over(
            MockEngine { request ->
                seen += request
                bodies += request.body.toByteArray().decodeToString()
                respond(body, HttpStatusCode.fromValue(status), headersOf(*headers.map { it.key to listOf(it.value) }.toTypedArray()))
            },
        )

    @Test
    fun `should send the method, headers and body the definition gives`() = runTest {
        client().send(
            HttpCall(
                "https://acme.test/usage?x=1", "POST",
                mapOf("Authorization" to "Bearer k", "Content-Type" to "application/json"), """{"a":1}""".encodeToByteArray(),
            ),
        )

        val request = seen.single()
        assertEquals("POST", request.method.value)
        assertEquals("https://acme.test/usage?x=1", request.url.toString())
        assertEquals("Bearer k", request.headers["Authorization"])
        assertEquals("application/json", request.body.contentType.toString())
        assertEquals("""{"a":1}""", bodies.single())
    }

    @Test
    fun `should answer with any status, its headers and its body`() = runTest {
        val response = client(503, mapOf("Retry-After" to "30"), "down").send(HttpCall("https://acme.test/"))

        assertEquals(503, response.status)
        assertEquals("30", response.header("retry-after"))
        assertEquals("down", response.text)
    }

    @Test
    fun `should only ever ask this Mac's own servers when certificates aren't checked`() = runTest {
        val loopback = LoopbackNetworkClient(client())

        val refused = try {
            loopback.send(HttpCall("https://example.com/"))
            null
        } catch (error: IllegalArgumentException) {
            error
        }
        assertNotNull(refused)
        assertTrue(seen.isEmpty())
        assertEquals(200, loopback.send(HttpCall("https://127.0.0.1:4242/status")).status)
        assertTrue(LoopbackNetworkClient.isLoopback("http://localhost:8080/x"))
        assertFalse(LoopbackNetworkClient.isLoopback("https://127.0.0.2/"))
    }

    @Test
    fun `should follow a redirect on this Mac's server only to the same address`() = runTest {
        val answers = object : NetworkClient {
            val asked = mutableListOf<String>()
            override suspend fun send(call: HttpCall): Response {
                asked += call.url
                return when (call.url) {
                    "https://127.0.0.1:4242/a" -> Response(302, mapOf("Location" to "/b"), ByteArray(0))
                    "https://127.0.0.1:4242/b" -> Response(302, mapOf("Location" to "https://evil.test/c"), ByteArray(0))
                    else -> Response(200, body = ByteArray(0))
                }
            }
        }

        val response = LoopbackNetworkClient(answers).send(HttpCall("https://127.0.0.1:4242/a"))

        assertEquals(302, response.status)
        assertEquals(listOf("https://127.0.0.1:4242/a", "https://127.0.0.1:4242/b"), answers.asked)
    }
}
