package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.CommandCall
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.ErrorFact
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * `command` — a CLI run over pipes; its exit code is a fact, never ignored. Checked at the
 * fetcher: the response it answers and the failure it reports. How a data source maps that
 * response and words that failure (`errors`) is the data source's suite.
 */
class CommandTest {
    private val usage = """{"cli":"acme","args":["usage","--json"],"environment":{"set":{"ACME_TOKEN":"{{token}}"}}}"""

    private fun call(json: String) = DefinitionJson.decodeFromString(CommandCall.serializer(), json)

    private fun fetcher(call: CommandCall, executor: FakeCLIExecutor, environments: MutableList<ProcessEnvironment> = mutableListOf()) =
        CommandFetcher(call, { environment -> environments += environment; executor }, { "/dedicated" })

    private fun executor(output: String, exitCode: Int = 0, found: Boolean = true) =
        FakeCLIExecutor(if (found) "/usr/local/bin/acme" else null) { CLIResult(output, exitCode) }

    @Test
    fun `should show the quota a command prints`() = runBlocking {
        val response = fetcher(call(usage), executor("""{"used":30}""")).fetch(Credential(mapOf("token" to "k")))

        assertEquals("""{"used":30}""", response.text)
    }

    @Test
    fun `should fail at fetching, naming the exit code, when the command exits with an error`() {
        val failure = assertThrows<CLIExitError> {
            runBlocking { fetcher(call(usage), executor("""{"used":30}""", exitCode = 2)).fetch(Credential(mapOf("token" to "k"))) }
        }

        assertEquals(ErrorFact.CliNonzero, failure.fact)
        assertEquals(UsageError.ExecutionFailed("`acme` exited with code 2"), failure.reason)
    }

    @Test
    fun `should say the CLI is not found, and not be ready, when it isn't installed`() {
        val fetcher = fetcher(call(usage), executor("", found = false))

        val failure = assertThrows<CLIMissingError> { runBlocking { fetcher.fetch(Credential(mapOf("token" to "k"))) } }

        assertEquals(UsageError.CliNotFound("acme"), failure.reason)
        assertFalse(fetcher.isReady())
    }

    @Test
    fun `should say the CLI is missing in the definition's words when it disappears just before running`() {
        val executor = FakeCLIExecutor { throw UsageError.CliNotFound("acme") }

        val failure = assertThrows<CLIMissingError> { runBlocking { fetcher(call("""{"cli":"acme"}"""), executor).fetch(null) } }

        // The fact the definition's `errors["cli.missing"]` words.
        assertEquals(ErrorFact.CliMissing, failure.fact)
    }

    @Test
    fun `should show the quota when the command is given its input text`() = runBlocking {
        val executor = FakeCLIExecutor { if (it.input == "/usage\n/quit\n") CLIResult("""{"used":30}""") else CLIResult("", 1) }

        val response = fetcher(call("""{"cli":"acme","input":"/usage\n/quit\n"}"""), executor).fetch(null)

        assertEquals("""{"used":30}""", response.text)
    }

    @Test
    fun `should hand the key to the command only through its environment`() {
        val environment = ProcessEnvironment(set = mapOf("ACME_TOKEN" to "{{token}}")).filled(Credential(mapOf("token" to "k-1")))

        assertEquals(mapOf("ACME_TOKEN" to "k-1"), environment.set)
    }

    @Test
    fun `should ask to sign in when the command's environment needs a key there isn't`() {
        assertThrows<UsageError.AuthenticationRequired> { ProcessEnvironment(set = mapOf("ACME_TOKEN" to "{{token}}")).filled(null) }
    }

    @Test
    fun `should tell a piped command from a terminal CLI in the definition`() {
        val command = Fetch.from(Json.parseToJsonElement("""{"command":$usage}"""))
        val terminal = Fetch.from(Json.parseToJsonElement("""{"cli":{"cli":"acme","input":"/usage"}}"""))

        assertEquals(listOf("usage", "--json"), (command as Fetch.Command).call.args)
        assertEquals("/usage", (terminal as Fetch.Cli).call.input)
    }
}
