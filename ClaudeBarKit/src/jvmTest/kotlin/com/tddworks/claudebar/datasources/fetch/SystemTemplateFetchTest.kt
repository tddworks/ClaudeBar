package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** The HTTPFetcher case of SystemTemplateTests: `{{system.x}}` comes from the fetch's own clock. */
class SystemTemplateFetchTest {
    /** 2026-10-05 14:30:00 UTC. */
    private val now = 1_791_210_600.0

    @Test
    fun `should ask for the day from the fetch's own clock`() = runTest {
        var seen: String? = null
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                seen = call.url
                return Response(200, body = "{}".encodeToByteArray())
            }
        }
        val request = HTTPRequest("https://api.example.com/costs?start_time={{system.day-29.epoch}}", timeout = 5.0)

        HTTPFetcher(request, network) { now }.fetch(Credential(mapOf("token" to "t")))

        assertEquals("https://api.example.com/costs?start_time=1788652800", seen)
    }
}
