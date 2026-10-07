package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *SET UP* as the definition says it. Whether a login waits to be set up, and the notice it
 * shows, go through `Provider` and are the lifecycle's to test.
 */
class NotSetUpTest {
    @Test
    fun `should tell the person how to set up Claude Code and where`() {
        val setup = TestDefinitions.builtIn("claude").setup!!

        assertEquals("See your session and weekly limits", setup.title)
        assertTrue(setup.text.contains("Claude Code"))
        assertEquals("https://claude.ai/code", setup.url)
        assertEquals("Set up Claude Code", setup.button)
    }

    @Test
    fun `should offer a plain Set up button when a setup names none, and no setup for Grok`() {
        val json = """{"title":"Install Acme","text":"Acme reads your limits through its CLI.","url":"https://acme.dev/cli"}"""
        val setup = ProviderDefinition.Setup.from(Json.parseToJsonElement(json))

        assertEquals(ProviderDefinition.Setup("Install Acme", "Acme reads your limits through its CLI.", "https://acme.dev/cli"), setup)
        assertEquals("Set up", setup.button)
        assertNull(TestDefinitions.builtIn("grok").setup)
    }

    @Test
    fun `should name the provider and say what failed when it has no setup of its own`() {
        val claude = TestDefinitions.builtIn("claude")
        val definition = ProviderDefinition(profile = claude.profile, dataSources = claude.dataSources, defaultDataSource = "cli")
        val notice = ProviderDefinition.Setup.fallback(definition.profile.name, UsageError.CliNotFound("acme"))

        assertNull(definition.setup)
        assertEquals("Set up Claude", notice.title)
        assertEquals(UsageError.CliNotFound("acme").message, notice.text)
        assertNull(notice.url)
    }
}
