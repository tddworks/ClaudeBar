package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.CredentialRefresh
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *CLI location* (#210), as the definition says it: the CLI's name and the other places it may
 * be, and the same definition running the chosen binary. Which binary a login runs, and
 * signing in with it, go through `Provider` and are the lifecycle's to test.
 */
class CLILocationTest {
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
