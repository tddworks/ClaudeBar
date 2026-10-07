package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.AnsweringNetwork
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.thrown
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/**
 * The loopback client a local server is asked through: certificates aren't checked, so it asks
 * only this Mac and follows a redirect only to the same scheme, host and port. (Swift's
 * `LoopbackRedirectTests`, the second suite of `LocalServerTests.swift`.)
 */
class LoopbackRedirectTest {
    /** A local server whose `/usage` redirects to [location] and whose every other path answers 200. */
    private fun server(location: String) = AnsweringNetwork { call ->
        if (call.url.endsWith("/usage")) Response(302, mapOf("Location" to location), ByteArray(0))
        else Response(200, body = """{"ok":true}""".encodeToByteArray())
    }

    @Test
    fun `should reject a remote request before opening a connection`() = runTest {
        val inner = AnsweringNetwork()

        val error = thrown { LoopbackNetworkClient(inner).send(HttpCall("https://example.invalid/usage")) }

        assertTrue(error is IllegalArgumentException, "$error")
        assertTrue(inner.sent.isEmpty())
    }

    @Test
    fun `should follow redirects within the same local server`() = runTest {
        val inner = server("https://127.0.0.1:5001/status")

        val response = LoopbackNetworkClient(inner).send(HttpCall("https://127.0.0.1:5001/usage"))

        assertEquals(200, response.status)
        assertEquals(listOf("https://127.0.0.1:5001/usage", "https://127.0.0.1:5001/status"), inner.sent.map { it.url })
    }

    @ParameterizedTest
    @ValueSource(strings = ["https://example.com/status", "https://127.0.0.1:8888/status"])
    fun `should refuse local server redirects to another origin`(destination: String) = runTest {
        val inner = server(destination)

        val response = LoopbackNetworkClient(inner).send(HttpCall("https://127.0.0.1:5001/usage"))

        assertEquals(302, response.status)
        assertEquals(listOf("https://127.0.0.1:5001/usage"), inner.sent.map { it.url })
    }
}
