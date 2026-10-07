package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.RefreshOutcome
import com.tddworks.claudebar.providers.StubbedProvider
import com.tddworks.claudebar.providers.refreshNow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Feature: Codex Configuration
 *
 * Users switch Codex between RPC and API probe modes.
 * API mode uses OAuth credentials from ~/.codex/auth.json.
 *
 * Codex is a definition (`codex.json`) run by the one `Provider`; these scenarios run that real
 * definition over stubbed connections, with `~` a fresh temporary folder.
 *
 * Behaviors covered:
 * - #33: User switches Codex to API mode → uses ChatGPT backend API instead of RPC
 * - #34: API mode shows credential status (found / not found)
 * - #351: A failed key lookup names its step
 */
class CodexConfigSpec {
    private val products = StubbedProducts()
    private val stub = StubbedProvider()
    private val settings = IsolatedSettings()

    @AfterEach
    fun cleanUp() {
        products.cleanUp()
        stub.cleanUp()
    }

    /** Codex from its definition, its settings in a settings.json of its own. */
    private fun codex(): Provider = stub.make(stub.builtIns.definition("codex"), settings = settings.repository)

    // Scenario: Switch probe mode (#33)

    @Test
    fun `should show the API's quotas, not the app server's, after the person switches Codex to API mode`() = runTest {
        stub.writeCodexAuth(token = "token")
        stub.answerRPC("""{"result":{"rateLimits":{"primary":{"usedPercent":20}}}}""")
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":55}}}""")
        val codex = codex()
        assertEquals("rpc", codex.configuration.activeKind)

        codex.configuration.use("api")
        products.monitor(codex).refresh("codex")

        // The API's answer (45% left) is shown, not RPC's (80%).
        assertEquals("api", codex.configuration.activeKind)
        assertEquals(45.0, codex.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
    }

    @Test
    fun `should use the data source the Codex card saves, RPC by default`() {
        val codex = codex()
        assertEquals("rpc", codex.configuration.activeKind)

        settings.repository.setDataSourceKind("api", "codex")

        assertEquals("api", settings.reopened().dataSourceKind("codex"))
        assertEquals("api", codex.configuration.activeKind)
    }

    // Scenario: A failed key lookup names its step (#351)

    @Test
    fun `should keep the last usage and its source, and say the key couldn't be read, when the Codex key disappears (#351)`() {
        stub.writeCodexAuth(token = "token")
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":38}}}""")
        val codex = codex()
        codex.configuration.use("api")
        assertTrue(codex.refreshNow(codex.defaultAccount) is RefreshOutcome.Refreshed)

        File(stub.home, ".codex/auth.json").delete()
        val outcome = codex.refreshNow(codex.defaultAccount)

        // The popover can say "Couldn't read your key", the last usage still on screen, last seen via API.
        assertTrue(outcome is RefreshOutcome.Failed, "expected a failure, got $outcome")
        assertEquals(DataSourceError.Step.LOOKUP, codex.defaultAccount.lastFailedStep)
        assertEquals(62.0, codex.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
        assertEquals("API", codex.defaultAccount.answeredByLabel)
    }

    // Scenario: API mode credential availability (#34)

    @Test
    fun `should find no API key until the person has logged in to Codex`() {
        val codex = codex()
        assertFalse(codex.hasKey("api", codex.defaultAccount))

        stub.writeCodexAuth(token = "token")

        assertTrue(codex.hasKey("api", codex.defaultAccount))
    }
}
