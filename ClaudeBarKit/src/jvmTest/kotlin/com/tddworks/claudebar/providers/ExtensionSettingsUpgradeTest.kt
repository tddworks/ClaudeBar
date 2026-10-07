package com.tddworks.claudebar.providers

import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * Extensions become definitions (docs/features/extensions/design.md): what a person saved for
 * an extension moves once — values into the provider's settings, secrets from UserDefaults
 * into the vault.
 */
class ExtensionSettingsUpgradeTest {
    private val file = temporarySettingsFile()
    private val defaults = MemoryLegacyStore()
    private val settings = JsonProviderSettings(file, MemoryLegacyStore())

    private fun definition(): ProviderDefinition = Extensions.definition(
        """
        {"id":"acme","name":"Acme","version":"1",
         "config":[{"id":"apiKey","label":"API Key","type":"secret"},{"id":"region","label":"Region","type":"string"}],
         "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
        """.trimIndent(),
        TestDefinitions.folder("ext-upgrade").path,
    )

    @Test
    fun `should keep an extension's saved value in its provider settings and its secret in the vault after the upgrade`() {
        file.write("extensions.acme.region", JsonPrimitive("eu"))
        defaults.values["com.claudebar.credentials.ext-acme-apiKey"] = "sk-1"
        val vault = MemoryVault()

        ExtensionSettingsUpgrade.run(listOf(definition()), file, settings, vault, defaults)

        assertEquals("eu", settings.value("region", "ext-acme"))
        assertEquals("sk-1", vault.secret("apiKey", "ext-acme"))
        assertNull(defaults.string("com.claudebar.credentials.ext-acme-apiKey"))
    }

    @Test
    fun `should keep the person's later change when the extension upgrade runs again`() {
        file.write("extensions.acme.region", JsonPrimitive("eu"))
        ExtensionSettingsUpgrade.run(listOf(definition()), file, settings, MemoryVault(), defaults)
        settings.setValue("us", "region", "ext-acme")

        ExtensionSettingsUpgrade.run(listOf(definition()), file, settings, MemoryVault(), defaults)

        assertEquals("us", settings.value("region", "ext-acme"))
    }
}
