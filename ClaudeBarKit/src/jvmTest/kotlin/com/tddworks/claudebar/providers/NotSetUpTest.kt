package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *NOT SET UP* — a login with no usage whose tool isn't on this Mac, or that has never signed
 * in, is waiting to be set up, not failing (#198). The definition's `setup` says what that
 * takes; a real failure stays one.
 */
class NotSetUpTest {
    private val claude = StubbedProvider("claude")

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    private fun cliNotFound() {
        claude.cli.located = { null }
        claude.cli.answer = { throw UsageError.CliNotFound("claude") }
    }

    private fun provider(settings: InMemoryProviderSettings = claude.settings) =
        claude.make(TestDefinitions.builtIn("claude"), settings = settings)

    @Test
    fun `should wait to be set up when Claude Code is not installed and never signed in (#198)`() {
        cliNotFound()
        val provider = provider()

        provider.refreshPlain()

        assertTrue(provider.defaultAccount.needsSetup)
    }

    @Test
    fun `should wait to be set up on the API when Claude Code is not installed and never signed in`() {
        cliNotFound()
        val provider = provider(InMemoryProviderSettings(dataSourceKinds = mapOf("claude" to "api")))

        provider.refreshPlain()

        assertTrue(provider.defaultAccount.needsSetup)
    }

    @Test
    fun `should show a failure, not set up, when Claude Code is installed but fails`() {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { throw UsageError.ExecutionFailed("claude is not running") }
        val provider = provider()

        provider.refreshPlain()

        assertNotNull(provider.defaultAccount.lastError)
        assertFalse(provider.defaultAccount.needsSetup)
    }

    @Test
    fun `should not wait to be set up when the login has never been refreshed`() {
        assertFalse(provider().defaultAccount.needsSetup)
    }

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
    fun `should show Claude's own setup notice when Claude Code is not set up`() {
        cliNotFound()
        val provider = provider()
        provider.refreshPlain()

        assertEquals("See your session and weekly limits", provider.setupNotice(provider.defaultAccount).title)
        assertEquals("Set up Claude Code", provider.setupNotice(provider.defaultAccount).button)
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

    @Test
    fun `should read no usage history when the login has none`() {
        assertFalse(provider().defaultAccount.readsUsage)
    }
}
