package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/**
 * *Export…* and *Import provider* (USER_JOURNEYS moments 10–11): a shared file carries the
 * key's NAME, never its value (F9); importing says where a key will be sent and shows every
 * command before anything is saved (F10).
 */
class SharingTest {
    private val root = TestDefinitions.folder("sharing")

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
    }

    private fun catalog(directory: File = File(root, "providers")) =
        ProviderCatalog(TestDefinitions.builtIns, directory.path, File(root, "extensions").path)

    private fun gateway(id: String = "custom-team-gateway-1a2b3c"): ProviderDefinition {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://llm.example.com/v1/usage"
        draft.key = ProviderDraft.KeySource.ApiKey
        draft.measure = ProviderDraft.Measure.Money(currency = "USD")
        draft.remaining = "$.remaining"
        draft.limit = "$.limit"
        draft.name = "Team Gateway"
        return draft.definition(id)
    }

    private fun tool(): ProviderDefinition {
        val draft = ProviderDraft(ProviderDraft.Start.Cli)
        draft.command = "teamtool usage --json"
        draft.measure = ProviderDraft.Measure.PercentLeft
        draft.remaining = "$.left"
        draft.name = "Team Tool"
        return draft.definition("custom-team-tool-9f8e7d")
    }

    @Test
    fun `should name the key, never hold it, when a provider is exported`() {
        val file = gateway().exported()

        assertTrue(file.contains("\"setting\" : \"apiKey\""))
        assertFalse(file.contains("origin"))
        assertFalse(file.contains("sk-"))
    }

    @Test
    fun `should say where the key will be sent and what it needs when a provider is imported`() {
        val review = catalog().review(gateway().exported())

        assertEquals("Team Gateway", review.definition.profile.name)
        assertEquals(ProviderProfile.Origin.CUSTOM, review.definition.profile.origin)
        assertEquals(listOf("llm.example.com"), review.sendsKeyTo)
        assertTrue(review.runs.isEmpty())
        assertEquals(listOf("apiKey"), review.needs)
    }

    @Test
    fun `should show the command it will run when a CLI provider is imported`() {
        val review = catalog().review(tool().exported())

        assertEquals(listOf("teamtool usage --json"), review.runs)
        assertTrue(review.sendsKeyTo.isEmpty())
        assertTrue(review.needs.isEmpty())
    }

    @Test
    fun `should keep an imported provider's id unless a provider already has it`() {
        val catalog = catalog()
        val gateway = gateway()

        val fresh = catalog.review(gateway.exported())
        catalog.add(gateway)
        val again = catalog.review(gateway.exported())
        val builtIn = catalog.review(TestDefinitions.builtIn("codex").exported())

        assertEquals(gateway.id, fresh.definition.id)
        assertNotEquals(gateway.id, again.definition.id)
        assertTrue(again.definition.id.startsWith("custom-team-gateway-"))
        assertNotEquals("codex", builtIn.definition.id)
        assertEquals(ProviderProfile.Origin.CUSTOM, builtIn.definition.profile.origin)
    }

    @Test
    fun `should save an imported provider among the person's own`() {
        val catalog = catalog()

        val saved = catalog.import(catalog.review(gateway().exported()))

        assertEquals(listOf(saved.id), catalog.custom().map { it.id })
        assertEquals(gateway().dataSources, saved.dataSources)
    }

    @Test
    fun `should refuse to import a file that is not a provider`() {
        assertThrows<Exception> { catalog().review("{}") }
    }
}
