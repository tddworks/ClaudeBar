package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSource
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.CredentialRefresh
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *CLI location* — where a provider's CLI lives on this Mac, when it isn't the one ClaudeBar
 * finds on its own (#210). One fact per provider: every login, every CLI data source and Add
 * Account's sign-in run it.
 */
class CLILocationTest {
    private val path = "/opt/tools/bin/codex-work"
    private val app = "/Applications/Codex.app/Contents/Resources/codex"
    private val stub = StubbedProvider("codex")

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun cli(source: DataSource): String? = when (val fetch = source.definition.fetch) {
        is Fetch.Cli -> fetch.call.cli
        is Fetch.JsonRpc -> fetch.call.cli
        else -> null
    }

    private fun Provider.clis(account: Account = defaultAccount) = dataSources(account).mapNotNull(::cli)

    private fun login(id: String) =
        ProviderAccountConfig(id, "", "$id@example.com", probeConfig = mapOf("codexHome" to "/tmp/$id", "chatgptAccountId" to id))

    @Test
    fun `should run the CLI inside the app when it isn't on the PATH`() {
        val codex = stub.makeProvider("codex", listOf(login("work")), isExecutable = { it == app }, locate = { null })

        for (account in codex.accounts.all) assertTrue(codex.clis(account).all { it == app })
        assertNull(codex.configuration.cliPath)
    }

    @Test
    fun `should run the CLI on the PATH even when the app carries one`() {
        val codex = stub.makeProvider("codex", isExecutable = { true }, locate = { "/usr/local/bin/codex" })

        assertTrue(codex.clis().all { it == "codex" })
    }

    @Test
    fun `should never run the app's copy when the chosen location is missing`() {
        stub.settings.setCLIPath("/custom/missing/codex", "codex")

        val codex = stub.makeProvider("codex", isExecutable = { it == app }, locate = { null })

        assertTrue(codex.clis().all { it == "/custom/missing/codex" })
    }

    @Test
    fun `should sign in with the CLI inside the app`() {
        val codex = stub.makeProvider("codex", isExecutable = { it == app }, locate = { null })
        val process = ScriptedSignIn(status = 1)

        runBlocking { codex.accounts.signIn(stub.signIn(process)) }

        assertEquals(app, process.launches.single().first)
    }

    @Test
    fun `should run the CLI from the chosen location for every login`() {
        val codex = stub.makeProvider("codex", listOf(login("work")), isExecutable = { true })

        codex.configuration.setCLIPath(path).done()

        for (account in codex.accounts.all) {
            val clis = codex.clis(account)
            assertFalse(clis.isEmpty())
            assertTrue(clis.all { it == path })
        }
        assertEquals(path, codex.configuration.cliPath)
        assertEquals(path, stub.settings.cliPath("codex"))
    }

    @Test
    fun `should go back to finding the CLI as usual when the location is cleared`() {
        val codex = stub.makeProvider("codex", isExecutable = { true })
        codex.configuration.setCLIPath(path).done()

        codex.configuration.setCLIPath("  ").done()

        assertNull(codex.configuration.cliPath)
        assertTrue(codex.clis().all { it == "codex" })
        assertNull(stub.settings.cliPath("codex"))
    }

    @Test
    fun `should refuse a location that is not a program and change nothing`() {
        val codex = stub.makeProvider("codex", isExecutable = { false })

        assertTrue(codex.configuration.setCLIPath("/Users/me/notes.txt") is Outcome.Refused)

        assertNull(codex.configuration.cliPath)
        assertTrue(codex.clis().all { it == "codex" })
    }

    @Test
    fun `should use the saved CLI location after a relaunch`() {
        stub.makeProvider("codex", isExecutable = { true }).configuration.setCLIPath(path).done()

        val relaunched = stub.makeProvider("codex")

        assertTrue(relaunched.clis().all { it == path })
    }

    @Test
    fun `should sign in a new account with the CLI at the chosen location`() {
        val codex = stub.makeProvider("codex", isExecutable = { true })
        codex.configuration.setCLIPath(path).done()
        val process = ScriptedSignIn(status = 1)

        runBlocking { codex.accounts.signIn(stub.signIn(process)) }

        assertEquals(path, process.launches.single().first)
    }

    private fun acme(cli: String) = ProviderDefinition.parse(
        """
        { "profile": { "id": "acme", "name": "Acme" }, "cli": $cli, "enabledByDefault": true,
          "defaultDataSource": "cli",
          "dataSources": [ { "kind": "cli", "fetch": { "jsonRpc": { "cli": "acme", "call": "usage/read" } },
                             "mapping": { "json": { "quotas": [] } } } ] }
        """.trimIndent(),
    )

    @Test
    fun `should run the name listed first and keep the other places`() {
        val definition = acme("""["acme", "/Applications/Acme.app/acme"]""")

        assertEquals("acme", definition.cli)
        assertEquals(listOf("/Applications/Acme.app/acme"), definition.cliPlaces)
    }

    @Test
    fun `should keep a CLI with no other place as one name`() {
        val definition = acme("\"acme\"")

        val json = definition.toJson().toString()

        assertTrue(definition.cliPlaces.isEmpty())
        assertTrue(json.contains(""""cli":"acme""""))
    }

    @Test
    fun `should refresh API credentials with the chosen CLI`() {
        val definition = TestDefinitions.builtIn("gemini").runningCLI("/opt/tools/gemini")
        val credential = definition.dataSource("api")?.credential as CredentialLookup.Refreshing
        val refresh = (credential.refresh as CredentialRefresh.Cli).call

        assertEquals("/opt/tools/gemini", refresh.cli)
        assertEquals("/quit\n", refresh.input)
        assertTrue("GEMINI_API_KEY" in refresh.environment.unset)
    }

    @Test
    fun `should keep terminal input timing when the CLI location changes`() {
        val definition = TestDefinitions.builtIn("kimi")
        val before = (definition.dataSource("cli")?.fetch as Fetch.Cli).call
        val after = (definition.runningCLI("/opt/tools/kimi").dataSource("cli")?.fetch as Fetch.Cli).call

        assertEquals(1.5, before.inputDelay)
        assertEquals(before.inputDelay, after.inputDelay)
        assertEquals("/opt/tools/kimi", after.cli)
    }
}
