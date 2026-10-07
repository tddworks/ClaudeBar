package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.FileCall
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.WorkingDirectory
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.mapping.Amount
import com.tddworks.claudebar.datasources.mapping.JSONMapping
import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.datasources.mapping.QuotaRule
import com.tddworks.claudebar.datasources.mapping.ResetRef
import com.tddworks.claudebar.datasources.mapping.ValueRef
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/**
 * *Add Provider* (USER_JOURNEYS moments 5–9): the sheet's answers become a definition — the
 * same data the built-ins are — and run on the same `Provider` and `DataSource`.
 */
class AddProviderTest {
    private val root = TestDefinitions.folder("catalog")

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
    }

    private fun catalog() = ProviderCatalog(TestDefinitions.builtIns, File(root, "providers").path, File(root, "extensions").path)

    /** Ken's OpenRouter: an API, his own key, money of a limit. */
    private fun openRouter(): ProviderDraft {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = ProviderDraft.KeySource.ApiKey
        draft.sentAs = ProviderDraft.SentAs.Bearer
        draft.measure = ProviderDraft.Measure.Money(currency = "USD")
        draft.remaining = "$.data.limit_remaining"
        draft.limit = "$.data.limit"
        draft.name = "OpenRouter"
        draft.symbol = "dollarsign.circle"
        return draft
    }

    private fun jsonMapping(definition: ProviderDefinition): JSONMapping =
        (definition.dataSources.first().mapping as Mapping.Json).mapping

    // Start from API

    @Test
    fun `should ask the API the person typed, with the key they saved, when they start from an API`() {
        val definition = openRouter().definition("custom-openrouter-1a2b3c")

        assertEquals("custom-openrouter-1a2b3c", definition.id)
        assertEquals("OpenRouter", definition.profile.name)
        assertEquals(ProviderProfile.Origin.CUSTOM, definition.profile.origin)
        assertEquals("dollarsign.circle", definition.profile.look.symbol)
        val source = definition.dataSources.first()
        assertEquals("api", definition.defaultDataSource)
        assertEquals(CredentialLookup.Setting("apiKey"), source.credential)
        val request = (source.fetch as Fetch.Http).request
        assertEquals("https://openrouter.ai/api/v1/auth/key", request.url)
        assertEquals(mapOf("Authorization" to "Bearer {{token}}", "Accept" to "application/json"), request.headers)
    }

    @Test
    fun `should send a key from an environment variable in the header the person chose`() {
        val draft = openRouter()
        draft.key = ProviderDraft.KeySource.Environment("OPENROUTER_API_KEY")
        draft.sentAs = ProviderDraft.SentAs.Header("X-API-Key")

        val source = draft.definition("custom-x").dataSources.first()

        assertEquals(CredentialLookup.Environment("OPENROUTER_API_KEY"), source.credential)
        assertEquals("{{token}}", (source.fetch as Fetch.Http).request.headers["X-API-Key"])
    }

    @Test
    fun `should show money of its limit, with no reset, when the drafted provider is refreshed`() {
        val network = StubNetwork { call ->
            if (call.headers["Authorization"] == "Bearer sk-or-1") Response(200, body = """{"data":{"limit_remaining":12.4,"limit":50}}""".encodeToByteArray())
            else Response(401, body = ByteArray(0))
        }
        val stub = StubbedProvider(network = network)
        val vault = MemoryVault(mapOf("custom-openrouter.apiKey" to "sk-or-1"))
        val definition = openRouter().definition("custom-openrouter")
        val provider = stub.make(definition, vault = vault)

        val usage = provider.refreshPlain().usage()

        val quota = usage.quotas.first()
        assertEquals(Left.Balance(Money(12_400_000_000, "USD"), Money(50_000_000_000, "USD")), quota.left)
        assertNull(quota.resetsAtSeconds)
        stub.cleanUp()
    }

    @Test
    fun `should show no percentage when the person maps no limit`() {
        val draft = openRouter()
        draft.limit = null

        val json = jsonMapping(draft.definition("custom-x"))

        assertEquals(
            QuotaRule.MoneyLeft(money = Amount.Value(listOf(ValueRef.Path("$.data.limit_remaining"))), of = null, currency = "USD"),
            json.quotas.first().left,
        )
    }

    @Test
    fun `should show a percentage used with its reset when the person maps both`() {
        val draft = openRouter()
        draft.measure = ProviderDraft.Measure.PercentUsed
        draft.used = "$.usage.percent"
        draft.resets = "$.usage.resets_at"
        draft.resetsFormat = ProviderDraft.ResetsFormat.ISO8601

        val json = jsonMapping(draft.definition("custom-x"))

        assertEquals(listOf(ValueRef.Path("$.usage.percent")), json.quotas.first().usedPercent)
        assertEquals(listOf(ResetRef.Iso8601("$.usage.resets_at")), json.quotas.first().resetsAt)
    }

    // Start from CLI · File

    @Test
    fun `should run the command the person typed, from the dedicated folder, when they start from a CLI`() {
        val draft = ProviderDraft(ProviderDraft.Start.Cli)
        draft.command = """mytool usage --format "json""""
        draft.measure = ProviderDraft.Measure.PercentLeft
        draft.remaining = "$.left"
        draft.name = "My Tool"

        val source = draft.definition("custom-mytool").dataSources.first()

        assertEquals("cli", source.kind)
        // A command a person types runs over pipes; only a TUI needs a terminal.
        val call = (source.fetch as Fetch.Command).call
        assertEquals("mytool", call.cli)
        assertEquals(listOf("usage", "--format", "json"), call.args)
        assertEquals(WorkingDirectory.DEDICATED, call.workingDirectory)
        assertNull(source.credential)
    }

    @Test
    fun `should read a CLI's text by the line that names the number`() {
        val draft = ProviderDraft(ProviderDraft.Start.Cli)
        draft.command = "mytool status"
        draft.measure = ProviderDraft.Measure.PercentLeft
        draft.textLabel = "Quota"
        draft.name = "My Tool"

        val text = (draft.definition("custom-mytool").dataSources.first().mapping as Mapping.Text).mapping

        assertEquals("Quota", text.quotas.first().label)
        assertNotNull(text.quotas.first().leftPercent)
    }

    @Test
    fun `should read the file the person chose when they start from a file`() {
        val draft = ProviderDraft(ProviderDraft.Start.File)
        draft.path = "~/.mytool/usage.json"
        draft.measure = ProviderDraft.Measure.PercentUsed
        draft.used = "$.used"
        draft.name = "My Tool"

        val source = draft.definition("custom-mytool").dataSources.first()

        assertEquals("file", source.kind)
        assertEquals(Fetch.File(FileCall(PathPattern("~/.mytool/usage.json"))), source.fetch)
    }

    @Test
    fun `should say what is missing when a draft lacks what it needs`() {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.name = "Nameless"

        assertThrows<ProviderDraft.Missing> { draft.definition("custom-x") }
    }

    // Copy a provider

    @Test
    fun `should run the same data sources under a new id and name, as custom, when a provider is copied`() {
        val codex = TestDefinitions.builtIn("codex")
        val draft = ProviderDraft(ProviderDraft.Start.Copy(codex))
        draft.name = "Codex (work)"

        val copy = draft.definition("custom-codex-work")

        assertEquals("custom-codex-work", copy.id)
        assertEquals("Codex (work)", copy.profile.name)
        assertEquals(ProviderProfile.Origin.CUSTOM, copy.profile.origin)
        assertEquals(codex.dataSources, copy.dataSources)
        assertEquals(codex.profile.look, copy.profile.look)
    }

    // Map fields

    @Test
    fun `should offer each value of a response as a path to click`() {
        val fields = ResponseFields(Response(status = 200, body = """{"data":{"limit":50,"label":"key","items":[{"x":1}],"ok":true}}""".encodeToByteArray()))

        assertEquals(listOf("$.data.items.0.x", "$.data.label", "$.data.limit", "$.data.ok"), fields.map { it.path })
        assertEquals("50", fields.first { it.path == "$.data.limit" }.value)
        assertTrue(fields.first { it.path == "$.data.limit" }.isNumber)
        assertFalse(fields.first { it.path == "$.data.label" }.isNumber)
    }

    @Test
    fun `should offer a response's lines when it is not JSON`() {
        val fields = ResponseFields(Response("Quota: 42% left\nPlan: Pro"))

        assertTrue(fields.isEmpty())
        assertEquals(listOf("Quota: 42% left", "Plan: Pro"), ResponseFields.lines(Response("Quota: 42% left\nPlan: Pro")))
    }

    // The catalog

    @Test
    fun `should bring a saved provider back as custom until it is removed`() {
        val catalog = catalog()
        val definition = openRouter().definition(catalog.mintId("OpenRouter"))

        catalog.add(definition)
        val saved = catalog.custom()
        catalog.remove(definition.id)

        assertEquals(listOf(definition.id), saved.map { it.id })
        assertEquals(ProviderProfile.Origin.CUSTOM, saved.first().profile.origin)
        assertEquals(definition.dataSources, saved.first().dataSources)
        assertTrue(catalog.custom().isEmpty())
    }

    @Test
    fun `should mint an id that is never just the name and never a built-in's`() {
        val catalog = catalog()

        val first = catalog.mintId("Codex")
        val second = catalog.mintId("Codex")

        assertTrue(first.startsWith("custom-codex-"))
        assertNotEquals(first, second)
        assertNull(TestDefinitions.builtIns[first])
    }

    @Test
    fun `should keep no key in a saved provider's file`() {
        val catalog = catalog()
        val definition = openRouter().definition("custom-openrouter")

        catalog.add(definition)
        val text = File(catalog.directory, "custom-openrouter.json").readText()

        assertTrue(text.contains("\"setting\" : \"apiKey\""))
        assertFalse(text.contains("sk-"))
    }

    // Draft connection

    @Test
    fun `should let a connection be tested before anything is mapped`() {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://example.com/usage"
        draft.name = "Example"

        val source = draft.connection()

        assertEquals(CredentialLookup.Setting("apiKey"), source.credential)
        assertEquals(Mapping.Json(JSONMapping(quotas = emptyList())), source.mapping)
        assertThrows<ProviderDraft.Missing.Used> { draft.definition("x") }
    }
}

/** Screens that only hold an id find a custom provider's face and name too. */
class CustomRegistryTest {
    @Test
    fun `should find a registered custom provider by its lineup id until it is unregistered`() {
        val draft = ProviderDraft(ProviderDraft.Start.File)
        draft.path = "~/usage.json"
        draft.used = "$.used"
        draft.name = "Local Tool"
        val definition = draft.definition("custom-local-tool-abc123")
        val stub = StubbedProvider()
        val factory = ProviderFactory(
            Engine(InMemoryProviderSettings(), stub.connections(), stub.home, { null }, stub.folders, HomePaths(stub.home), { true }, { it }, now = { 0.0 }),
            TestDefinitions.builtIns,
        )

        factory.customs.register(definition)
        val found = factory.definition("custom-local-tool-abc123")
        factory.customs.unregister(definition.id)

        assertEquals("Local Tool", found?.profile?.name)
        assertNull(factory.definition("custom-local-tool-abc123"))
        assertEquals("codex", factory.definition("codex.work")?.id)
        stub.cleanUp()
    }
}
