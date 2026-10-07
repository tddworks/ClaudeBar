package com.tddworks.claudebar.activity

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A real listener on 127.0.0.1, on a free port, leaving its port file in a temporary home. */
class HookHttpServerTest {
    private val discovery = PortDiscovery.inHome("${NSTemporaryDirectory()}hook-server-${NSUUID().UUIDString}")
    private val server = HookHttpServer(discovery, defaultPort = 0, nowSeconds = { 1_700_000_000.0 })

    private fun test(block: suspend () -> Unit) = runBlocking { withContext(Dispatchers.Default) { withTimeout(10_000) { block() } } }

    private val payload = """{"session_id": "abc", "hook_event_name": "SessionStart", "cwd": "/tmp/project"}"""

    @Test
    fun `should hand over the event a hook posts with its Claude Code process`() = test {
        val events = server.start()
        val client = HttpClient()

        val response = client.post("http://127.0.0.1:${server.actualPort}/hook") {
            header(HookConstants.PROCESS_ID_HEADER, "4242")
            setBody(payload)
        }

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(
            SessionEvent("abc", SessionEvent.EventName.SESSION_START, "/tmp/project", 1_700_000_000.0, processId = 4242),
            events.first(),
        )
        client.close()
        server.stop()
    }

    @Test
    fun `should answer but hand over nothing for a request that is not a hook's post`() = test {
        val events = server.start()
        val client = HttpClient()

        val response = client.get("http://127.0.0.1:${server.actualPort}/hook")
        client.post("http://127.0.0.1:${server.actualPort}/other") { setBody(payload) }
        client.post("http://127.0.0.1:${server.actualPort}/hook") { setBody("not json") }
        client.close()
        server.stop()

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(emptyList(), events.toList())
    }

    @Test
    fun `should leave its port for the hook while it listens and take it away when it stops`() = test {
        server.start()

        assertTrue(server.actualPort > 0)
        assertEquals(server.actualPort, discovery.readPort())

        server.stop()
        assertNull(discovery.readPort())
    }
}
