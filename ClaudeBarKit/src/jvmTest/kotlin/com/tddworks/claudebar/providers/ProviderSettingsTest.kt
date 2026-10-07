package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SecretVault
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.net.URI

/** *REGION*, *API KEY*, *CLI DATA FOLDER* on a provider no vendor ships: one form, two scopes, filled into each login's data sources. */
class ProviderSettingsTest {
    private val acmeJson = """
    {"profile":{"id":"acme","name":"Acme","links":{"dashboard":"https://console.{{setting.region.site}}/usage"}},
     "settings":[
       {"id":"region","label":"Region","scope":"account","default":"china",
        "kind":{"choice":[{"id":"china","label":"China","site":"acme.cn"},
                          {"id":"international","label":"International","site":"acme.com"}]}},
       {"id":"apiKey","label":"API key","scope":"account","kind":"secret"},
       {"id":"home","label":"CLI data folder","scope":"account","default":"/Users/me/.acme","kind":{"path":{"mustExist":true}}}],
     "dataSources":[{"kind":"api","credential":{"setting":"apiKey"},
       "fetch":{"http":{"url":"https://api.{{setting.region.site}}/usage","headers":{"Authorization":"Bearer {{token}}"}}},
       "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}],
     "defaultDataSource":"api"}
    """

    private val network = StubNetwork { Response(200, body = """{"used":10}""".encodeToByteArray()) }
    private val stub = StubbedProvider(network = network)
    private val settings = InMemoryProviderSettings()
    private val vault = MemoryVault()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private val hosts: List<String> get() = network.sent.map { URI(it.url).host }
    private val authorizations: List<String> get() = network.sent.mapNotNull { it.headers["Authorization"] }

    private fun provider(paths: FakePaths = FakePaths(setOf("/Users/me/.acme", "/Users/me/.acme-work"))) =
        stub.make(ProviderDefinition.parse(acmeJson), settings.accounts("acme"), vault = vault, paths = paths, settings = settings)

    private fun providerWith(vault: SecretVault) =
        stub.make(ProviderDefinition.parse(acmeJson), vault = vault, paths = FakePaths(setOf("/Users/me/.acme-work")), settings = settings)

    @Test
    fun `should ask the default region when nothing is chosen`() {
        val acme = provider()
        acme.configuration.set("apiKey", "sk-default").done()

        acme.refreshPlain()

        assertEquals(listOf("api.acme.cn"), hosts)
    }

    @Test
    fun `should ask the new region and open its dashboard once the region is changed`() {
        val acme = provider()
        acme.configuration.set("apiKey", "sk-default").done()
        acme.configuration.set("region", "international").done()

        acme.refreshPlain()

        assertEquals(listOf("api.acme.com"), hosts)
        assertEquals("international", settings.value("region", "acme"))
        assertEquals("https://console.acme.com/usage", acme.plainDashboardURL)
    }

    @Test
    fun `should use an added login's own region and key over the provider's, never keeping the key in plain settings`() {
        val acme = provider()
        val work = acme.accounts.add(filling = mapOf("region" to "international", "apiKey" to "sk-work", "home" to "/Users/me/.acme-work")).done()

        acme.refreshNow(work)

        assertEquals(listOf("api.acme.com"), hosts)
        assertEquals(listOf("Bearer sk-work"), authorizations)
        assertEquals("https://console.acme.com/usage", acme.dashboardURL(work))
        assertNull(work.values["apiKey"])
    }

    @Test
    fun `should tell a key is saved without ever showing it`() {
        val acme = provider()
        val key = acme.definition.setting("apiKey")!!
        assertFalse(acme.configuration.hasSaved(key, acme.defaultAccount))

        acme.configuration.set("apiKey", "sk-default").done()
        assertTrue(acme.configuration.hasSaved(key, acme.defaultAccount))
        assertNull(acme.configuration.value(key, acme.defaultAccount))

        acme.configuration.set("apiKey", null).done()
        assertFalse(acme.configuration.hasSaved(key, acme.defaultAccount))
    }

    @Test
    fun `should refuse a region that is not one of its options`() {
        val acme = provider()
        assertEquals(
            Outcome.Refused("Choose a Region from the list."),
            acme.accounts.add(filling = mapOf("region" to "mars", "apiKey" to "sk", "home" to "/Users/me/.acme-work")),
        )
        assertEquals(Outcome.Refused("Choose a Region from the list."), acme.configuration.set("region", "mars"))
    }

    @Test
    fun `should refuse a folder another login already uses, the default login's included`() {
        val acme = provider()
        assertTrue(acme.accounts.add(filling = mapOf("apiKey" to "sk", "home" to "/Users/me/.acme")) is Outcome.Refused)
        acme.accounts.add(filling = mapOf("apiKey" to "sk", "home" to "/Users/me/.acme-work")).done()
        assertTrue(acme.accounts.add(filling = mapOf("apiKey" to "sk-2", "home" to "/Users/me/.acme-work")) is Outcome.Refused)
        assertEquals(2, acme.accounts.size)
    }

    @Test
    fun `should add no login when the Keychain does not keep its key`() {
        val acme = providerWith(RefusingVault())
        assertEquals(
            Outcome.Refused("ClaudeBar couldn't keep this key securely. The account wasn't added."),
            acme.accounts.add(filling = mapOf("apiKey" to "sk", "home" to "/Users/me/.acme-work")),
        )
        assertEquals(1, acme.accounts.size)
    }

    @Test
    fun `should keep the old key when the Keychain will not replace it`() {
        val vault = ReplacementRefusingVault(mapOf("acme.apiKey" to "sk-old"))
        val acme = providerWith(vault)

        assertTrue(acme.configuration.set("apiKey", "sk-new") is Outcome.Refused)

        assertEquals("sk-old", vault.secret("apiKey", "acme"))
    }

    @Test
    fun `should refuse a provider that declares a setting both for itself and in its login form`() {
        val json = acmeJson.replace(
            """"defaultDataSource":"api"}""",
            """"defaultDataSource":"api","accounts":{"form":[{"id":"region","label":"Region","choices":["x"]}]}}""",
        )
        assertThrows<DefinitionError> { ProviderDefinition.parse(json) }
    }

    @Test
    fun `should show in Settings the address the default login asks, in its chosen region`() {
        val acme = provider()
        acme.configuration.set("region", "international").done()

        val fetch = acme.configuration.definitionAsRun.dataSource("api")?.fetch as Fetch.Http
        assertEquals("https://api.acme.com/usage", fetch.request.url)
    }

    @Test
    fun `should show in Settings only the settings the default login uses`() {
        val json = """
        {"profile":{"id":"tool","name":"Tool"},"cli":"tool","defaultDataSource":"cli",
         "settings":[{"id":"home","label":"Home","scope":"account","kind":"path"},
                     {"id":"envVar","label":"Env","default":"TOOL_KEY"}],
         "dataSources":[{"kind":"cli","credential":{"environment":"{{setting.envVar}}"},
           "fetch":{"command":{"cli":"tool"}},"mapping":{"json":{"quotas":[]}}}],
         "accounts":{"patch":{"cli":{"fetch":{"command":{"environment":{"set":{"HOME":"{{account.home}}"}}}}}}}}
        """
        assertEquals(listOf("envVar"), ProviderDefinition.parse(json).defaultLoginSettings.map { it.id })
        assertEquals(listOf("region", "apiKey"), ProviderDefinition.parse(acmeJson).defaultLoginSettings.map { it.id })
    }

    @Test
    fun `should list on import every host a key may be sent to, one per region`() {
        assertEquals(listOf("api.acme.cn", "api.acme.com"), ProviderDefinition.parse(acmeJson).keyDestinations)
    }
}

/** A Keychain that keeps a key once, then seems to take a new value but overwrites it with garbage — a replacement that doesn't read back. */
private class ReplacementRefusingVault(secrets: Map<String, String>) : SecretVault {
    val secrets = secrets.toMutableMap()
    override fun secret(name: String, provider: String) = secrets["$provider.$name"]
    override fun save(value: String, name: String, provider: String) {
        val key = "$provider.$name"
        secrets[key] = if (secrets[key] == null) value else "corrupted"
    }
    override fun delete(name: String, provider: String) = secrets.remove("$provider.$name") != null
}
