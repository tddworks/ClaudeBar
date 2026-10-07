package com.tddworks.claudebar.providers

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** A provider-scope setting's value lives at `<id>.<setting>` — today's keys, so a region chosen before the form was data is read as it was. */
class JSONSettingsRepositorySettingValueTest {
    private val store = temporarySettingsFile()
    private val repository = JsonProviderSettings(store, MemoryLegacyStore())

    @Test
    fun `should remember a provider's setting under the provider and setting name`() {
        repository.setValue("international", "region", "acme")

        assertEquals("international", repository.value("region", "acme"))
        assertEquals("international", store.string("acme.region"))
    }

    @Test
    fun `should keep a region chosen before settings were data`() {
        store.write("kimi.region", JsonPrimitive("international"))

        assertEquals("international", repository.value("region", "kimi"))
    }

    @Test
    fun `should fall back to the setting's default once its value is forgotten`() {
        repository.setValue("international", "region", "acme")

        repository.setValue(null, "region", "acme")

        assertNull(repository.value("region", "acme"))
    }

    @Test
    fun `should keep a value an old card saved under another name, and move it when changed`() {
        store.write("vercel.authEnvVar", JsonPrimitive("MY_GATEWAY_KEY"))

        assertEquals("MY_GATEWAY_KEY", repository.value("authEnvVar", "vercel-gateway"))

        repository.setValue("OTHER_KEY", "authEnvVar", "vercel-gateway")
        assertEquals("OTHER_KEY", store.string("vercel-gateway.authEnvVar"))
        assertNull(store.string("vercel.authEnvVar"))
    }

    @Test
    fun `should show a list an old card saved as comma-separated text`() {
        store.write("bedrock.regions", JsonArray(listOf(JsonPrimitive("us-east-1"), JsonPrimitive("eu-west-1"))))

        assertEquals("us-east-1, eu-west-1", repository.value("regions", "bedrock"))
    }

    @Test
    fun `should show a number an old card saved as text`() {
        store.write("copilot.monthlyLimit", JsonPrimitive(300))

        assertEquals("300", repository.value("monthlyLimit", "copilot"))
    }

    @Test
    fun `should keep a value an old card saved in UserDefaults, and move it to settings-json when changed`() {
        val defaults = MemoryLegacyStore("com.claudebar.credentials.github-username" to "octocat")
        val repository = JsonProviderSettings(store, defaults)

        assertEquals("octocat", repository.value("username", "copilot"))

        repository.setValue("hubot", "username", "copilot")
        assertEquals("hubot", store.string("copilot.username"))
        assertFalse(defaults.contains("com.claudebar.credentials.github-username"))
    }
}
