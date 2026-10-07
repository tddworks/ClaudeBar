package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *Test Connection* — the active data source looks up its key and fetches, stopping before
 * mapping, so a person sees what came back or which step failed.
 */
class TestConnectionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun stub(dataSourceKind: String? = null) = StubbedProvider("codex", dataSourceKind).also { stubs += it }

    @Test
    fun `should show the status the provider answered with when the connection works`() {
        val stub = stub("api")
        stub.writeCodexAuth(accountId = "me")
        stub.answerHTTP("""{"anything":"unmapped"}""")
        val codex = stub.makeProvider("codex")

        val result = runBlocking { codex.testConnection() }

        assertEquals(200, (result as ConnectionOutcome.Answered).response.status)
    }

    @Test
    fun `should say the key lookup failed when there is no key`() {
        val stub = stub("api")
        val codex = stub.makeProvider("codex")

        val result = runBlocking { codex.testConnection() }

        assertEquals(DataSourceError.Step.LOOKUP, (result as ConnectionOutcome.Failed).error.step)
    }

    @Test
    fun `should allow background refreshes once the person has tested the connection`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20}}}}""")
        val codex = stub.makeProvider("codex")

        runBlocking { codex.testConnection() }

        assertEquals(true, stub.settings.isOn("verifiedAtLeastOnce", "codex"))
    }
}

/** The fallback a definition lets the person switch off — Claude's API → CLI. */
class FallbackSettingTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    @Test
    fun `should use the fallback until the person switches it off, and remember the choice`() {
        val settings = InMemoryProviderSettings()
        val provider = stub.make(TestDefinitions.builtIn("claude"), settings = settings)

        assertTrue(provider.configuration.isFallbackEnabled("api"))

        provider.configuration.setFallbackEnabled(false, "api")

        assertFalse(provider.configuration.isFallbackEnabled("api"))
        assertEquals(false, settings.isOn("cliFallbackEnabled", "claude"))
    }

    @Test
    fun `should always use a fallback the person cannot switch off`() {
        val provider = stub.makeProvider("claude")

        provider.configuration.setFallbackEnabled(false, "cli")

        assertTrue(provider.configuration.isFallbackEnabled("cli"))
    }
}
