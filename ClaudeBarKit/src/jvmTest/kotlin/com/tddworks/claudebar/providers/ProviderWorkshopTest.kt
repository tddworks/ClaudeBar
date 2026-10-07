package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.AnsweringNetwork
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.testDataSources
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** *Add Provider* and *Import* as the sheets run them: tried before anything is saved, then saved with their keys. */
class ProviderWorkshopTest {
    private val stub = StubbedProvider()
    private val settings = InMemoryProviderSettings()
    private val vault = MemoryVault()
    private val folder = TestDefinitions.folder("workshop")
    private val catalog = ProviderCatalog(TestDefinitions.builtIns, File(folder, "providers").path, File(folder, "extensions").path)
    private val network = AnsweringNetwork.answering("""{"left": 40}""")
    private val providers = Providers(emptyList(), catalog, settings, vault, CustomDefinitions(), ::make)
    private val workshop = ProviderWorkshop(providers, catalog, TestDefinitions.builtIns, testDataSources(network = network), vault)

    @AfterEach
    fun cleanUp() {
        stub.cleanUp()
        folder.deleteRecursively()
    }

    private fun make(definition: ProviderDefinition) = stub.make(definition, settings.accounts(definition.id), settings = settings)

    private fun acme(): ProviderDraft = ProviderDraft(ProviderDraft.Start.Api).apply {
        url = "https://acme.example/usage"
        key = ProviderDraft.KeySource.ApiKey
        sentAs = ProviderDraft.SentAs.Bearer
        measure = ProviderDraft.Measure.PercentLeft
        remaining = "$.left"
        name = "Acme"
    }

    @Test
    fun `should show what came back when the person tests a draft with the key they typed`() = runTest {
        val outcome = workshop.testConnection(acme(), "sk-typed")

        assertTrue(outcome is ConnectionOutcome.Answered)
        assertEquals("Bearer sk-typed", network.sent.single().headers["Authorization"])
    }

    @Test
    fun `should say which step failed when a draft's test can't connect`() = runTest {
        val refusing = ProviderWorkshop(
            providers, catalog, TestDefinitions.builtIns,
            testDataSources(network = AnsweringNetwork.answering("nope", status = 500)), vault,
        )

        val outcome = refusing.testConnection(acme(), "sk-typed")

        assertEquals(DataSourceError.Step.FETCH, (outcome as ConnectionOutcome.Failed).error.step)
    }

    @Test
    fun `should preview the quota a draft reads from the answer`() {
        val preview = workshop.preview(acme(), Response(200, body = """{"left": 40}""".encodeToByteArray()))

        assertEquals(40.0, (preview as DraftPreview.Usage).usage.quotas.single().percentRemaining)
    }

    @Test
    fun `should say what the draft still needs before it can preview`() {
        val draft = acme().apply { url = "" }

        val preview = workshop.preview(draft, Response(200, body = "{}".encodeToByteArray()))

        assertTrue(preview is DraftPreview.Incomplete)
    }

    @Test
    fun `should save the provider, and its key in the vault, when the person adds a draft`() {
        val provider = workshop.add(acme(), "sk-saved").valueOrNull!!

        assertEquals("Acme", provider.name)
        assertEquals(listOf(provider.id), providers.all.map { it.id })
        assertEquals("sk-saved", vault.secret("apiKey", provider.id))
    }

    @Test
    fun `should save the keys typed in a review when the person imports a shared file`() {
        val shared = acme().definition("custom-acme-share").exported()
        val review = workshop.review(shared).valueOrNull!!

        val provider = workshop.import(review, mapOf("apiKey" to "sk-imported")).valueOrNull!!

        assertEquals("sk-imported", vault.secret("apiKey", provider.id))
    }

    @Test
    fun `should refuse a shared file that isn't a definition`() {
        val outcome = workshop.review("{ not json")

        assertTrue(outcome is Outcome.Refused)
    }
}
