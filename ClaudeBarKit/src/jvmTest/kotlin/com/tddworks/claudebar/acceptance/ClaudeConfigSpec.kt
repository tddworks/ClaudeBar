package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.monitoring.StubbedProducts
import com.tddworks.claudebar.providers.ClaudeHarness
import com.tddworks.claudebar.providers.claudeResponse
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Feature: Claude Configuration
 *
 * Users switch Claude between CLI and API probe modes.
 * API mode uses OAuth credentials for direct HTTP calls.
 *
 * Claude is a definition (`claude.json`) run by the one `Provider`; these scenarios run that real
 * definition, its mapping scripts and the Claude card's settings keys (in a settings.json of its
 * own) over a stubbed terminal, network and home folder.
 *
 * Behaviors covered:
 * - #28: User switches Claude to API mode → uses OAuth HTTP API instead of CLI
 * - #29: API mode shows credential status (found / not found)
 * - #30: Expired session shows user-friendly error message
 */
class ClaudeConfigSpec {
    private val usageScreen = """
        Current session
        ████████████████░░░░ 80% left
        Resets in 2h 15m
    """.trimIndent()

    private val apiUsage = """{"five_hour":{"utilization":55}}"""

    private val products = StubbedProducts()
    private val claude = ClaudeHarness()
    private val settings = IsolatedSettings().also { it.repository.setEnabled(true, "claude") }

    @AfterEach
    fun cleanUp() {
        products.cleanUp()
        claude.cleanUp()
    }

    private fun cliAnswers(screen: String) {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { CLIResult(screen) }
    }

    private fun apiAnswers(body: String, status: Int = 200) = claude.answer { claudeResponse(status, body = body) }

    /** `~/.claude/.credentials.json`, as `claude login` leaves it. */
    private fun loggedIn() = claude.writeCredentials(accessToken = "token", refreshToken = "refresh", subscriptionType = "claude_max")

    /** What the Claude card saves when the person picks the API. */
    private fun chooseAPI() = settings.repository.setDataSourceKind("api", "claude")

    /** What the Claude card saves when the person turns *CLI fallback* off. */
    private fun turnCLIFallbackOff() = settings.repository.setOn(false, "cliFallbackEnabled", "claude")

    private fun provider() = claude.provider(settings = settings.repository)

    // Scenario: Switch probe mode (#28)

    @Test
    fun `should show the API's quotas after the person switches Claude to API mode`() = runTest {
        cliAnswers(usageScreen)
        apiAnswers(apiUsage)
        loggedIn()
        val provider = provider()
        assertEquals("cli", provider.configuration.activeKind)

        chooseAPI()
        products.monitor(provider).refresh("claude")

        assertEquals("api", provider.configuration.activeKind)
        assertEquals(45.0, provider.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
    }

    @Test
    fun `should show the CLI's quotas in API mode when nobody is logged in to the API`() = runTest {
        cliAnswers(usageScreen)
        chooseAPI()
        val provider = provider()

        products.monitor(provider).refresh("claude")

        assertEquals(80.0, provider.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
        assertEquals("cli", provider.defaultAccount.answeredBy)
    }

    @Test
    fun `should show the API's quotas in CLI mode when the CLI screen shows no usage and the person is logged in`() = runTest {
        cliAnswers("Claude Code v2.1.0\nSomething unexpected")
        apiAnswers(apiUsage)
        loggedIn()
        val provider = provider()

        products.monitor(provider).refresh("claude")

        assertEquals(45.0, provider.defaultAccount.snapshot?.quotas?.first()?.percentRemaining)
        assertEquals("api", provider.defaultAccount.answeredBy)
        assertNull(provider.defaultAccount.lastError)
    }

    // Scenario: API mode credential availability (#29)

    @Test
    fun `should find the API key once the person has logged in to Claude`() {
        val provider = provider()
        assertFalse(provider.hasKey("api", provider.defaultAccount))

        loggedIn()

        assertTrue(provider.hasKey("api", provider.defaultAccount))
    }

    // Scenario: Expired session shows user-friendly error (#30)

    @Test
    fun `should tell the person their session expired, naming claude, when the saved login and its refresh are refused`() = runTest {
        chooseAPI()
        turnCLIFallbackOff()
        apiAnswers("", status = 401)
        loggedIn()
        val provider = provider()

        products.monitor(provider).refresh("claude")

        val description = provider.defaultAccount.lastError?.message.orEmpty()
        assertTrue(description.contains("Session expired"), description)
        assertTrue(description.contains("claude"), description)
    }
}
