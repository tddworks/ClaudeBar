package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.MemoryVault
import com.tddworks.claudebar.providers.ProviderCatalog
import com.tddworks.claudebar.providers.ProviderDraft
import com.tddworks.claudebar.providers.ProviderProfile
import com.tddworks.claudebar.providers.StubNetwork
import com.tddworks.claudebar.providers.StubbedProvider
import com.tddworks.claudebar.providers.TestDefinitions
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Feature: Add Provider
 *
 * USER_JOURNEYS §5 — "Add a custom provider from an API". Ken pays for a gateway ClaudeBar
 * doesn't ship and tracks its credits without a script.
 */
class AddProviderSpec {
    private val root = TestDefinitions.folder("add-provider")
    private val products = StubbedProducts()
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
        products.cleanUp()
        stubs.forEach { it.cleanUp() }
    }

    private fun catalog() = ProviderCatalog(TestDefinitions.builtIns, File(root, "providers").path, File(root, "extensions").path)

    // Scenario: Add a custom provider from an API

    @Test
    fun `should show Ken OpenRouter's credits, with no reset and no percentage, after adding it`() = runTest {
        // Given — Ken has an OpenRouter key
        val network = StubNetwork { call ->
            if (call.headers["Authorization"] == "Bearer sk-or-ken") {
                Response(200, body = """{"data":{"label":"ken","limit":50,"limit_remaining":12.4}}""".encodeToByteArray())
            } else {
                Response(401, body = ByteArray(0))
            }
        }
        val stub = StubbedProvider(network = network).also { stubs += it }

        // When — he adds a provider from "API" with the auth/key URL and his key, maps Remaining
        // and Limit, names it "OpenRouter" and saves
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = ProviderDraft.KeySource.ApiKey
        draft.measure = ProviderDraft.Measure.Money(currency = "USD")
        draft.remaining = "$.data.limit_remaining"
        draft.limit = "$.data.limit"
        draft.name = "OpenRouter"
        val catalog = catalog()
        val id = catalog.mintId(draft.name)
        catalog.add(draft.definition(id))
        val vault = MemoryVault(mapOf("$id.apiKey" to "sk-or-ken"))
        val saved = catalog.custom().first()
        val openRouter = stub.make(saved, vault = vault)
        val monitor = products.monitor(openRouter)
        monitor.refresh(openRouter.defaultAccount.id)

        // Then — "OpenRouter" appears with $12.40 of $50.00, no reset and no percentage of a window
        assertEquals(ProviderProfile.Origin.CUSTOM, saved.profile.origin)
        assertEquals(listOf("OpenRouter"), monitor.logins.map(monitor::lineupName))
        val credits = openRouter.defaultAccount.snapshot?.quotas?.firstOrNull()
        assertNotNull(credits)
        assertEquals(Left.Balance(Money(12_400_000_000, "USD"), Money(50_000_000_000, "USD")), credits?.left)
        assertNull(credits?.resetsAtSeconds)
        assertNull(credits?.window)
    }
}
