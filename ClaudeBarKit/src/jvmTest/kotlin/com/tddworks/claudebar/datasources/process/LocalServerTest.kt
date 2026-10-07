package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.LocalServerCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * An app that serves its usage on this Mac: found by its process, asked with what it was
 * started with, on the ports it listens on — loopback only. The loopback client's own rules
 * (no remote host, no cross-origin redirect) are the network adapter's suite.
 */
class LocalServerTest {
    private val callJson = """
        {"app":"Acme","process":{"names":["acme_server"],"match":["--app acme"]},
         "values":{"csrf":"--csrf[=\\s]+(\\S+)","httpPort":"--http_port[=\\s]+(\\d+)"},
         "required":["csrf"],
         "paths":["/usage","/status"],
         "plainHTTPPort":"httpPort",
         "headers":{"X-Csrf":"{{csrf}}"},
         "body":"{}"}
    """

    private val listening = "acme 42 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:5001 (LISTEN)\nacme 42 me 11u IPv4 0x1 0t0 TCP 127.0.0.1:5002 (LISTEN)"

    /** What the fetch asked: the URLs, the token header each carried, the commands it ran. */
    private class Seen {
        val urls = mutableListOf<String>()
        val csrf = mutableListOf<String?>()
        var commands = listOf<List<String>>()
    }

    private class Loopback(private val answering: Set<String>, private val seen: Seen) : NetworkClient {
        override suspend fun send(call: HttpCall): Response {
            seen.urls += call.url
            seen.csrf += call.headers["X-Csrf"]
            return Response(status = if (call.url in answering) 200 else 404, body = """{"ok":true}""".encodeToByteArray())
        }
    }

    private fun decode(json: String) = DefinitionJson.decodeFromString(LocalServerCall.serializer(), json)

    private fun fetch(pgrep: String, lsof: String = listening, answering: Set<String> = setOf("https://127.0.0.1:5002/status"), seen: Seen = Seen()): Response {
        val commands = FakeCLIExecutor { CLIResult(if (it.binary.endsWith("pgrep")) pgrep else lsof) }
        try {
            return runBlocking { LocalServerFetcher(decode(callJson), commands, Loopback(answering, seen)) { emptyList() }.fetch(null) }
        } finally {
            seen.commands = commands.executions.map { listOf(it.binary) + it.args }
        }
    }

    @Test
    fun `should ask the running app on each port it listens on, with the token it was started with, until one answers`() {
        val seen = Seen()

        val response = fetch("42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080", seen = seen)

        assertEquals(200, response.status)
        assertEquals(
            listOf("https://127.0.0.1:5001/usage", "https://127.0.0.1:5001/status", "https://127.0.0.1:5002/usage", "https://127.0.0.1:5002/status"),
            seen.urls,
        )
        assertTrue(seen.csrf.all { it == "tok-1" })
        assertEquals(listOf("/usr/bin/pgrep", "-lf", "acme_server"), seen.commands.first())
        assertEquals(listOf("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "42"), seen.commands.last())
    }

    @Test
    fun `should ask the plain HTTP port the app was started with last`() {
        val seen = Seen()

        fetch("42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080", answering = setOf("http://127.0.0.1:8080/usage"), seen = seen)

        assertEquals("http://127.0.0.1:8080/usage", seen.urls.last())
    }

    @Test
    fun `should treat the app as not running when only another app's process shares its name`() {
        assertThrows<CLIMissingError> { fetch("77 /Applications/Other.app/acme_server --csrf x") }
    }

    @Test
    fun `should treat the app as not running when no process is found`() {
        assertThrows<CLIMissingError> { fetch("") }
    }

    @Test
    fun `should ask to sign in when the app runs without its token`() {
        assertThrows<UsageError.AuthenticationRequired> { fetch("42 /opt/acme/acme_server --app acme") }
    }

    @Test
    fun `should say it couldn't connect to the app when no port answers`() {
        val failure = assertThrows<UsageError.ExecutionFailed> { fetch("42 /opt/acme/acme_server --app acme --csrf t", answering = emptySet()) }

        assertEquals(UsageError.ExecutionFailed("Could not connect to Acme"), failure)
    }

    @Test
    fun `should be ready only while the app itself is running, without starting a process to check`() {
        val call = decode("""{"app":"Acme","process":{"names":["acme_server"],"match":["/acme/"]},"paths":["/u"]}""")
        val nothing = Loopback(emptySet(), Seen())

        assertTrue(LocalServerFetcher(call, FakeCLIExecutor(), nothing) { listOf("/opt/acme/acme_server") }.isReady())
        assertFalse(LocalServerFetcher(call, FakeCLIExecutor(), nothing) { listOf("/Applications/Other.app/acme_server") }.isReady())
    }

    @Test
    fun `should list what it runs and where it asks for Import, and keep the definition when written out and read back`() {
        // What it reaches for Import (`Connection`) is the data source's; here the definition's round trip.
        val call = decode(callJson)
        val fetch = Fetch.LocalServer(call)

        assertEquals(call, decode(DefinitionJson.encodeToString(LocalServerCall.serializer(), call)))
        assertEquals(fetch, Fetch.from(fetch.toJson()))
        assertEquals(listOf("/usr/bin/pgrep", "-lf", "acme_server"), LocalServerFetcher.processQuery(call.process))
    }
}
