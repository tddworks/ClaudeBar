package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.IdentityField
import com.tddworks.claudebar.quotas.AccountTier
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/** Every definition the app ships reads, keeps the laws a definition keeps, and writes back the same. */
class BundledDefinitionsTest {
    private val files = File(TestDefinitions.FOLDER).listFiles { file -> file.extension == "json" }.orEmpty()
        .filter { (Json.parseToJsonElement(it.readText()) as JsonObject).containsKey("profile") }

    @Test
    fun `should read every bundled provider definition and keep its laws`() {
        assertEquals(27, files.size, "bundled definitions")
        for (file in files) {
            val definition = ProviderDefinition.parse(file.readText())
            definition.validate()
            assertEquals(file.nameWithoutExtension, definition.id, file.name)
            assertEquals(ProviderProfile.Origin.BUILT_IN, definition.profile.origin)
        }
        assertEquals(27, TestDefinitions.builtIns.all.size)
    }

    @Test
    fun `should write every bundled provider definition back the same`() {
        for (file in files) {
            val definition = ProviderDefinition.parse(file.readText())
            assertEquals(definition, ProviderDefinition.parse(definition.toJson().toString()), file.name)
            assertEquals(definition, ProviderDefinition.parse(definition.exported()), file.name)
        }
    }

    @Test
    fun `should give every bundled login its own data sources once the values it needs are filled`() {
        for (definition in TestDefinitions.builtIns.all.values) {
            val values = definition.accountSettings.associate { it.id to "/Users/me/${it.id}" } +
                (definition.accounts?.folder?.let { it.values("/Users/me/folder") + (it.accountId.savedAs to "id-1") } ?: emptyMap())
            val sources = runCatching { definition.dataSourcesForAccount(values) }
            assertTrue(sources.isSuccess || sources.exceptionOrNull() is DefinitionError, definition.id)
            sources.getOrNull()?.forEach { assertTrue(it.unfilled("account").isEmpty(), "${definition.id}.${it.kind}") }
        }
    }

    // The laws, one by one

    private fun definition(dataSources: String, default: String = "api", rest: String = "", links: String = "{}") = """
        {"profile":{"id":"acme","name":"Acme","links":$links},"defaultDataSource":"$default","dataSources":[$dataSources]$rest}
    """.trimIndent()

    private fun source(kind: String, extra: String = "") =
        """{"kind":"$kind","fetch":{"file":{"path":"~/x.json"}},"mapping":{"json":{"quotas":[]}}$extra}"""

    @Test
    fun `should refuse a definition with no data source`() {
        val error = assertThrows<DefinitionError> { ProviderDefinition.parse(definition("")) }
        assertEquals("Provider 'acme' has no data sources", error.message)
    }

    @Test
    fun `should refuse a definition that lists a data source twice`() {
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition("${source("api")},${source("api")}")) }
    }

    @Test
    fun `should refuse a definition whose default or fallback names a data source it doesn't have`() {
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api"), default = "cli")) }
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api", ""","fallback":"cli""""))) }
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api", ""","fallbackOn":{"noData":"cli"}"""))) }
    }

    @Test
    fun `should refuse a setting listed twice, or both as a setting and in the account form`() {
        val twice = ""","settings":[{"id":"key","label":"Key"},{"id":"key","label":"Key"}]"""
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api"), rest = twice)) }
        val both = ""","settings":[{"id":"key","label":"Key"}],"accounts":{"form":[{"id":"key","label":"Key"}]}"""
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api"), rest = both)) }
    }

    @Test
    fun `should refuse a sign-in with no folder to check`() {
        val signIn = ""","accounts":{"signIn":{"cli":"acme","args":["login"],"homeVariable":"ACME_HOME"}}"""
        assertThrows<DefinitionError> { ProviderDefinition.parse(definition(source("api"), rest = signIn)) }
    }

    @Test
    fun `should ask an added account for the settings in the old account form, as one form with the rest`() {
        val form = ""","accounts":{"form":[{"id":"apiKey","label":"API key","kind":"secret"}]}"""
        val acme = ProviderDefinition.parse(definition(source("api"), rest = form))

        assertEquals(listOf("apiKey"), acme.settings.map { it.id })
        assertEquals(Setting.Scope.ACCOUNT, acme.setting("apiKey")?.scope)
        assertEquals(listOf(AddAccountWay.FORM), acme.accounts?.ways)
    }

    @Test
    fun `should name an added login's folder values as the definition derives them`() {
        val folder = ProviderDefinition.Accounts.Folder(
            savedAs = "home", accountId = ProviderDefinition.Accounts.Folder.AccountId(IdentityField.CredentialValue("account"), "id"),
            derived = mapOf("item" to ProviderDefinition.Accounts.Folder.Derived("Acme-credentials-", 8)),
        )

        val values = folder.values("/Users/me/work")

        assertEquals("/Users/me/work", values["home"])
        assertEquals("Acme-credentials-" + sha256("/Users/me/work").take(8), values["item"])
    }

    @Test
    fun `should leave a data source out of an added login when its patch says null, and fill the rest`() {
        val accounts = ""","settings":[{"id":"home","label":"Home","scope":"account","kind":"path"}],""" +
            """"accounts":{"patch":{"cli":null}}"""
        val acme = ProviderDefinition.parse(
            definition("""${source("api", ""","requiresFiles":["{{account.home}}/auth.json"]""")},${source("cli")}""", rest = accounts),
        )

        val sources = acme.dataSourcesForAccount(mapOf("home" to "/Users/me/work"))

        assertEquals(listOf("api"), sources.map { it.kind })
        assertEquals(listOf("/Users/me/work/auth.json"), sources.first().requiresFiles)
        assertThrows<DefinitionError> { acme.dataSourcesForAccount(emptyMap()) }
    }

    @Test
    fun `should show the settings the default login uses, never a folder only an added login has`() {
        val settings = ""","settings":[{"id":"region","label":"Region","default":"eu"},{"id":"home","label":"Home","scope":"account","kind":"path"}]"""
        val acme = ProviderDefinition.parse(
            definition(source("api", ""","requiresFiles":["{{account.home}}/auth.json"]"""), rest = settings, links = """{"dashboard":"https://{{setting.region}}.acme.dev"}"""),
        )

        assertEquals(listOf("region"), acme.defaultLoginSettings.map { it.id })
        assertEquals("https://eu.acme.dev", acme.profile.links.dashboard(null, mapOf("region" to "eu")))
        assertNull(acme.profile.links.dashboard)
    }

    @Test
    fun `should open the dashboard for the plan the usage reported`() {
        val links = ProviderDefinition.Links(dashboardTemplate = "https://acme.dev", dashboardByPlan = mapOf("claudeApi" to "https://console.acme.dev", "ULTRA" to "https://ultra.acme.dev"))

        assertEquals("https://console.acme.dev", links.dashboard(AccountTier.ClaudeApi))
        assertEquals("https://ultra.acme.dev", links.dashboard(AccountTier.Custom("ULTRA")))
        assertEquals("https://acme.dev", links.dashboard(AccountTier.ClaudePro))
    }

    private fun sha256(text: String): String = java.security.MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
        .joinToString("") { "%02x".format(it) }
}
