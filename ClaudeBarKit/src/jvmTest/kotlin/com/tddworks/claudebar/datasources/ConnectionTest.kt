package com.tddworks.claudebar.datasources

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Each fetch case answers for itself: where it may send a key, what it runs. */
class ConnectionTest {
    @Test
    fun `should name the URL an HTTP fetch reaches and run no command`() {
        val fetch = Fetch.Http(HTTPRequest(url = "https://acme.test/usage"))
        assertEquals(listOf("https://acme.test/usage"), fetch.urls)
        assertTrue(fetch.commands.isEmpty())
    }

    @Test
    fun `should name the URL of every step in a multi-step HTTP fetch`() {
        val fetch = Fetch.HttpSteps(
            HTTPSteps(
                listOf(
                    HTTPStep(name = "a", request = HTTPRequest(url = "https://a.test")),
                    HTTPStep(name = "b", request = HTTPRequest(url = "https://b.test")),
                ),
            ),
        )
        assertEquals(listOf("https://a.test", "https://b.test"), fetch.urls)
    }

    @Test
    fun `should name the command line that a piped command, a terminal CLI and JSON-RPC run`() {
        assertEquals(listOf(listOf("acme", "usage")), Fetch.Command(CommandCall(cli = "acme", args = listOf("usage"))).commands)
        assertEquals(listOf(listOf("acme", "--tui")), Fetch.Cli(CLICall(cli = "acme", args = listOf("--tui"))).commands)
        assertEquals(
            listOf(listOf("acme", "serve")),
            Fetch.JsonRpc(JSONRPCCall(cli = "acme", args = listOf("serve"), call = "usage")).commands,
        )
    }

    @Test
    fun `should run the CLI from the location found for it, leaving other CLIs and files alone`() {
        val fetch = Fetch.Command(CommandCall(cli = "acme", args = listOf("usage")))
        assertEquals(Fetch.Command(CommandCall(cli = "/opt/acme", args = listOf("usage"))), fetch.runningCLI("acme", "/opt/acme"))
        assertEquals(fetch, fetch.runningCLI("other", "/opt/other"))
        val file = Fetch.File(FileCall(PathPattern("~/x")))
        assertEquals(file, file.runningCLI("acme", "/opt/acme"))
    }
}
