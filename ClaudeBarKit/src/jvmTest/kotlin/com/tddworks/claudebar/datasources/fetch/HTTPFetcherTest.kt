package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.HTTPStatusError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import io.ktor.http.Url
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class HTTPFetcherTest {
    private val now = 1_700_000_000.0

    /** Answers every call the same, keeping what was sent. */
    internal class Answering(private val answer: (HttpCall) -> Response) : NetworkClient {
        val sent = mutableListOf<HttpCall>()
        override suspend fun send(call: HttpCall): Response = answer(call).also { sent += call }
    }

    // Retry-After

    @Test
    fun `should wait the seconds the server asks before trying again`() {
        assertEquals(120.0, HTTPFetcher.retryAfter("120", now))
        assertEquals(1.0, HTTPFetcher.retryAfter("1", now))
    }

    @Test
    fun `should not trust a server asking to wait zero seconds (anthropics-claude-code#30930)`() {
        // /api/oauth/usage has been seen answering Retry-After: 0 while still 429ing: no usable
        // value, so the caller applies its fallback window instead.
        assertNull(HTTPFetcher.retryAfter("0", now))
    }

    @Test
    fun `should wait until the future date the server gives before trying again`() {
        // 2023-11-14 22:13:20 UTC + 60s = 2023-11-14 22:14:20 UTC
        assertEquals(60.0, HTTPFetcher.retryAfter("Tue, 14 Nov 2023 22:14:20 GMT", now))
    }

    @Test
    fun `should not trust a try-again date in the past`() {
        assertNull(HTTPFetcher.retryAfter("Tue, 14 Nov 2023 22:00:00 GMT", now))
    }

    @Test
    fun `should not trust a try-again time that is missing, blank, negative or not a number`() {
        assertNull(HTTPFetcher.retryAfter(null, now))
        assertNull(HTTPFetcher.retryAfter("", now))
        assertNull(HTTPFetcher.retryAfter("   ", now))
        assertNull(HTTPFetcher.retryAfter("not a number", now))
        assertNull(HTTPFetcher.retryAfter("-5", now))
    }

    // 429

    private suspend fun fetch429(headers: Map<String, String>): HTTPStatusError? {
        val fetcher = HTTPFetcher(HTTPRequest("https://example.com"), Answering { Response(429, headers, ByteArray(0)) }) { now }
        return try {
            fetcher.fetch(null)
            null
        } catch (error: HTTPStatusError) {
            error
        }
    }

    @Test
    fun `should be rate limited for as long as the server says when it answers 429`() = runTest {
        val error = fetch429(mapOf("Retry-After" to "120"))

        assertEquals(429, error?.status)
        assertEquals(UsageError.RateLimited(now + 120), error?.reason)
    }

    @Test
    fun `should wait five minutes when the server answers 429 without a usable try-again time`() = runTest {
        val missing = fetch429(emptyMap())
        val zero = fetch429(mapOf("Retry-After" to "0"))

        assertEquals(UsageError.RateLimited(now + 300), missing?.reason)
        assertEquals(UsageError.RateLimited(now + 300), zero?.reason)
    }

    // Filling a URL

    @Test
    fun `should send a value with spaces and ampersands in a URL intact`() = runTest {
        val network = Answering { Response(200, body = "{}".encodeToByteArray()) }
        val fetcher = HTTPFetcher(HTTPRequest("https://acme.test/usage?org={{org}}"), network) { now }

        fetcher.fetch(Credential(mapOf("org" to "team & org")))

        val parameters = Url(network.sent.single().url).parameters
        assertEquals(listOf("org"), parameters.names().toList())
        assertEquals("team & org", parameters["org"])
    }
}
