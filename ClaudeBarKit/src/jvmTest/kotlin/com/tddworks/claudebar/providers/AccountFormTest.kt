package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *Add Account* by its form: a provider whose key is the person's own — an API someone added —
 * takes a second account by a second key. That key lives in the account's own corner of the
 * vault; a login without one of its own is *Key needed*, never the default login's key.
 */
class AccountFormTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** Ken's OpenRouter, made in Add Provider: his key, money of a limit. */
    private fun openRouter(): ProviderDefinition {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = ProviderDraft.KeySource.ApiKey
        draft.sentAs = ProviderDraft.SentAs.Bearer
        draft.measure = ProviderDraft.Measure.Money("USD")
        draft.remaining = "$.data.limit_remaining"
        draft.limit = "$.data.limit"
        draft.name = "OpenRouter"
        return draft.definition("custom-openrouter")
    }

    /** Answers by key: each account sees the money left on its own key. */
    private fun network(remaining: Map<String, Int>) = StubNetwork { call ->
        val key = call.headers["Authorization"]?.removePrefix("Bearer ") ?: ""
        val left = remaining[key]
        if (left == null) Response(401, body = ByteArray(0))
        else Response(200, body = """{"data":{"limit_remaining":$left,"limit":50}}""".encodeToByteArray())
    }

    private fun provider(
        definition: ProviderDefinition,
        vault: MemoryVault,
        network: StubNetwork,
        settings: InMemoryProviderSettings = InMemoryProviderSettings(),
    ): Provider {
        val stub = StubbedProvider(network = network).also { stubs += it }
        return stub.make(definition, settings.accounts(definition.id), vault = vault, settings = settings)
    }

    private fun money(left: Long) = Left.Balance(Money(left * 1_000_000_000, "USD"), Money(50 * 1_000_000_000L, "USD"))

    // The form, from the definition

    @Test
    fun `should ask a second account for its own key when the API is one someone added`() {
        val accounts = openRouter().accounts!!

        assertEquals(listOf(AddAccountWay.FORM), accounts.ways)
        assertEquals(listOf("apiKey"), accounts.form.map { it.id })
        assertEquals(Setting.Kind.Secret, accounts.form.first().kind)
    }

    @Test
    fun `should give an added login a key field of its own when the default login's key comes from an environment variable`() {
        val draft = ProviderDraft(ProviderDraft.Start.Api)
        draft.url = "https://example.test/usage"
        draft.key = ProviderDraft.KeySource.Environment("EXAMPLE_API_KEY")
        draft.measure = ProviderDraft.Measure.PercentUsed
        draft.used = "$.used"
        draft.name = "Example"
        val definition = draft.definition("custom-example")

        val added = definition.dataSourcesForAccount(emptyMap()).first()

        assertEquals(CredentialLookup.Environment("EXAMPLE_API_KEY"), definition.dataSources.first().credential)
        assertEquals(CredentialLookup.Setting("apiKey"), added.credential)
    }

    // Each account, its own key

    @Test
    fun `should show each account the money left on its own key`() {
        val vault = MemoryVault(mapOf("custom-openrouter.apiKey" to "sk-mine"))
        val openRouter = provider(openRouter(), vault, network(mapOf("sk-mine" to 40, "sk-work" to 7)))

        val work = openRouter.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()
        val theirs = openRouter.refreshNow(work).usage()
        val mine = openRouter.refreshPlain().usage()

        assertEquals(money(7), theirs.quotas.first().left)
        assertEquals(money(40), mine.quotas.first().left)
        assertEquals(AccountOrigin.FORM, work.madeBy)
    }

    @Test
    fun `should turn the provider on and put the account in the lineup when an account is added with its key`() {
        val openRouter = provider(openRouter(), MemoryVault(), network(emptyMap()))
        openRouter.isEnabled = false

        val work = openRouter.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()

        assertTrue(openRouter.isEnabled)
        assertTrue(openRouter.isInLineup(work))
    }

    @Test
    fun `should keep an account's key in the vault, never in the saved account`() {
        val vault = MemoryVault()
        val settings = InMemoryProviderSettings()
        val openRouter = provider(openRouter(), vault, network(emptyMap()), settings)

        val work = openRouter.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()

        assertEquals("sk-work", vault.secrets["${work.id}.apiKey"])
        assertNull(settings.accounts("custom-openrouter").first().probeConfig["apiKey"])
    }

    @Test
    fun `should fail at the lookup step, never borrowing the default's key, when an account has no key of its own`() {
        val vault = MemoryVault(mapOf("custom-openrouter.apiKey" to "sk-mine"))
        val openRouter = provider(openRouter(), vault, network(mapOf("sk-mine" to 40)))
        val work = openRouter.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()
        vault.secrets.remove("${work.id}.apiKey")

        assertTrue(openRouter.refreshNow(work) is RefreshOutcome.Failed)

        assertEquals(DataSourceError.Step.LOOKUP, work.lastFailedStep)
    }

    @Test
    fun `should refuse a field left empty and add nothing`() {
        val openRouter = provider(openRouter(), MemoryVault(), network(emptyMap()))

        assertTrue(openRouter.accounts.add(filling = mapOf("apiKey" to "  ")) is Outcome.Refused)
        assertEquals(1, openRouter.accounts.size)
    }

    @Test
    fun `should forget an account's keys when it is removed`() {
        val vault = MemoryVault()
        val openRouter = provider(openRouter(), vault, network(emptyMap()))
        val work = openRouter.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()

        openRouter.accounts.remove(work)

        assertNull(vault.secrets["${work.id}.apiKey"])
    }

    @Test
    fun `should bring back a saved form account with its key after a relaunch`() {
        val vault = MemoryVault()
        val settings = InMemoryProviderSettings()
        val first = provider(openRouter(), vault, network(mapOf("sk-work" to 7)), settings)
        first.accounts.add(filling = mapOf("apiKey" to "sk-work")).done()

        val relaunched = provider(openRouter(), vault, network(mapOf("sk-work" to 7)), settings)
        val usage = relaunched.refreshNow(relaunched.accounts[1]).usage()

        assertEquals(money(7), usage.quotas.first().left)
    }
}
