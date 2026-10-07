package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * `Providers` — the providers you keep, the Providers pane (TARGET §2.1): create a custom one,
 * read them and the lineup, order them, delete a custom one.
 */
class KeptProvidersTest {
    private val stub = StubbedProvider()
    private val settings = InMemoryProviderSettings()
    private val vault = MemoryVault()
    private val customs = CustomDefinitions()
    private val folder = TestDefinitions.folder("kept-providers")
    private val catalog = ProviderCatalog(TestDefinitions.builtIns, File(folder, "providers").path, File(folder, "extensions").path)

    @AfterEach
    fun cleanUp() {
        stub.cleanUp()
        folder.deleteRecursively()
    }

    private fun make(definition: ProviderDefinition) = stub.make(definition, settings.accounts(definition.id), settings = settings)

    private fun providers(ids: List<String>) =
        Providers(ids.map { make(TestDefinitions.builtIn(it)) }, catalog, settings, vault, customs, ::make)

    private fun custom(name: String = "Acme"): ProviderDefinition {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://acme.example/usage"
        draft.key = ProviderDraft.KeySource.ApiKey
        draft.sentAs = ProviderDraft.SentAs.Bearer
        draft.measure = ProviderDraft.Measure.PercentLeft
        draft.remaining = "$.left"
        draft.name = name
        return draft.definition(catalog.mintId(name))
    }

    // Read

    @Test
    fun `should list the providers, and find each provider and login, in the order they were kept`() {
        val kept = providers(listOf("claude", "codex"))

        assertEquals(listOf("claude", "codex"), kept.all.map { it.id })
        assertEquals("Codex", kept.provider("codex")?.name)
        assertEquals("claude", kept.login("claude")?.providerId)
    }

    @Test
    fun `should leave a turned-off provider's logins out of the lineup`() {
        val kept = providers(listOf("claude", "codex"))

        kept.provider("codex")?.isEnabled = false

        assertEquals(listOf("claude"), kept.lineup.map { it.id })
    }

    // Update: the order

    @Test
    fun `should save the new order when the person moves a provider`() {
        val kept = providers(listOf("claude", "codex", "gemini"))

        kept.move("gemini", -2)

        assertEquals(listOf("gemini", "claude", "codex"), kept.all.map { it.id })
        assertEquals(listOf("gemini", "claude", "codex"), settings.providerOrder())
    }

    @Test
    fun `should list providers in the saved order, with ones it doesn't name after`() {
        settings.setProviderOrder(listOf("codex", "gone"))

        val kept = providers(listOf("claude", "codex"))

        assertEquals(listOf("codex", "claude"), kept.all.map { it.id })
    }

    @Test
    fun `should stop a provider at the end when it is moved past it`() {
        val kept = providers(listOf("claude", "codex"))

        kept.move("claude", 5)

        assertEquals(listOf("codex", "claude"), kept.all.map { it.id })
    }

    // Create

    @Test
    fun `should save a new custom provider and list it after the others`() {
        val kept = providers(listOf("claude"))
        val acme = custom()

        val added = kept.add(acme).done()

        assertEquals(listOf("claude", acme.id), kept.all.map { it.id })
        assertEquals(acme.id, added.id)
        assertEquals(listOf(acme.id), catalog.custom().map { it.id })
    }

    @Test
    fun `should refuse to add a provider that is already kept`() {
        val kept = providers(listOf("claude"))
        val acme = custom()
        kept.add(acme).done()

        assertTrue(kept.add(acme) is Outcome.Refused)
        assertEquals(2, kept.all.size)
    }

    // Delete

    @Test
    fun `should remove a deleted custom provider's file, keys and place in the list`() {
        val kept = providers(listOf("claude"))
        val acme = custom()
        kept.add(acme).done()
        vault.save("sk-1", "apiKey", acme.id)

        kept.remove(acme.id).done()

        assertEquals(listOf("claude"), kept.all.map { it.id })
        assertTrue(catalog.custom().isEmpty())
        assertNull(vault.secret("apiKey", acme.id))
        assertNull(customs[acme.id])
    }

    @Test
    fun `should refuse to delete a built-in provider`() {
        val kept = providers(listOf("claude"))

        assertTrue(kept.remove("claude") is Outcome.Refused)
        assertEquals(listOf("claude"), kept.all.map { it.id })
    }
}
