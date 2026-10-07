package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Claude as a `Provider` built from `claude.json`: which data source runs, when it hands over,
 * which failure is reported, the API's background floor, and guest passes.
 */
class ClaudeProviderTest {
    private val usageScreen = """
        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
    """.trimIndent()

    private val apiUsage = """{"five_hour":{"utilization":45,"resets_at":"2099-01-01T00:00:00Z"}}"""

    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    // Helpers

    private fun answerCLI(screen: String) {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { CLIResult(screen) }
    }

    private fun failCLI(error: UsageError = UsageError.ExecutionFailed("claude is not running")) {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { throw error }
    }

    private fun answerAPI(body: String = apiUsage, status: Int = 200, headers: Map<String, String> = emptyMap()) {
        claude.writeCredentials(subscriptionType = "claude_max")
        claude.answer { claudeResponse(status, headers, body) }
    }

    private fun api() = InMemoryProviderSettings(dataSourceKinds = mapOf("claude" to "api"))

    private fun snapshot(tier: AccountTier) =
        UsageSnapshot("claude", emptyList(), System.currentTimeMillis() / 1000.0, null, null, null, tier, null, null, null)

    // Identity

    @Test
    fun `should be Claude, on by default, run from the CLI, with no usage or error yet`() {
        val provider = claude.provider()

        assertEquals("claude", provider.id)
        assertEquals("Claude", provider.lineupName(provider.defaultAccount))
        assertEquals("claude", provider.defaultAccount.cliCommand)
        assertEquals("https://claude.ai/new#settings/usage", provider.plainDashboardURL)
        assertEquals("https://status.anthropic.com", provider.defaultAccount.statusPageURL)
        assertTrue(provider.isEnabled)
        assertEquals("cli", provider.configuration.activeKind)
        assertNull(provider.defaultAccount.snapshot)
        assertNull(provider.defaultAccount.lastError)
    }

    // CLI mode

    @Test
    fun `should show the usage screen when Claude reads from the CLI`() {
        answerCLI(usageScreen)
        val provider = claude.provider()

        val usage = provider.refreshPlain().usage()

        assertEquals(65.0, usage.sessionQuota?.percentRemaining)
        assertEquals("cli", provider.defaultAccount.answeredBy)
        assertFalse(provider.defaultAccount.isSyncing)
    }

    @Test
    fun `should show the usage API's quotas when the CLI fails`() {
        failCLI()
        answerAPI()
        val provider = claude.provider()

        val usage = provider.refreshPlain().usage()

        assertEquals(55.0, usage.sessionQuota?.percentRemaining)
        assertEquals("api", provider.defaultAccount.answeredBy)
        assertNull(provider.defaultAccount.lastError)
    }

    @Test
    fun `should report the CLI's failure when the CLI and the API both fail`() {
        failCLI(UsageError.ExecutionFailed("claude is not running"))
        answerAPI("", status = 500)
        val provider = claude.provider()

        assertEquals(RefreshOutcome.Failed(UsageError.ExecutionFailed("claude is not running")), provider.refreshPlain())
        assertEquals(UsageError.ExecutionFailed("claude is not running"), provider.defaultAccount.lastError)
    }

    @Test
    fun `should show the cost screen before trying the API when the account is billed by API`() {
        claude.cli.located = { "/usr/local/bin/claude" }
        claude.cli.answer = { run ->
            if ("/cost" in run) CLIResult("Total cost:            \$1.23\nTotal duration (API):  1m 30s")
            else CLIResult("/usage is only available for subscription plans.")
        }
        val provider = claude.provider()

        val usage = provider.refreshPlain().usage()

        assertEquals("cliCost", provider.defaultAccount.answeredBy)
        assertEquals(AccountTier.ClaudeApi, usage.accountTier)
        assertEquals(1_230_000_000L, usage.costUsage?.totalCostNanos)
        assertEquals(90.0, usage.costUsage?.apiDuration)
    }

    // API mode

    @Test
    fun `should fall back from the API to the CLI unless the person turns the fallback off`() {
        answerCLI(usageScreen)
        val allowed = api()
        val refused = InMemoryProviderSettings(dataSourceKinds = mapOf("claude" to "api"), flags = mapOf("claude.cliFallbackEnabled" to false))

        // No credentials: the api cannot answer.
        val withFallback = claude.provider(settings = allowed)
        val withoutFallback = claude.provider(settings = refused)

        assertTrue(withFallback.isPlainAvailable())
        assertFalse(withoutFallback.isPlainAvailable())
        assertEquals(65.0, withFallback.refreshPlain().usage().sessionQuota?.percentRemaining)
        assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), withoutFallback.refreshPlain())
    }

    @Test
    fun `should report the rate limit and not fall back to the CLI when the API is rate-limited`() {
        answerCLI(usageScreen)
        answerAPI("", status = 429, headers = mapOf("Retry-After" to "120"))
        val provider = claude.provider(settings = api())

        assertTrue(provider.refreshPlain() is RefreshOutcome.Failed)

        assertTrue(provider.defaultAccount.lastError is UsageError.RateLimited, "expected rateLimited, got ${provider.defaultAccount.lastError}")
        assertNull(provider.defaultAccount.snapshot)
    }

    @Test
    fun `should report the API's failure when the API and the CLI both fail`() {
        failCLI()
        answerAPI("", status = 500)
        val provider = claude.provider(settings = api())

        assertEquals(RefreshOutcome.Failed(UsageError.ExecutionFailed("HTTP error: 500")), provider.refreshPlain())
    }

    @Test
    fun `should refresh in the background no more than every fifteen minutes on the API, with no floor on the CLI`() {
        assertEquals(900.0, claude.provider(settings = api()).backgroundRefreshFloorSeconds)
        assertNull(claude.provider().backgroundRefreshFloorSeconds)
    }

    // Guest passes

    @Test
    fun `should offer guest passes to Max, not to Pro or API, nor before a refresh`() {
        val passes = GuestPasses(ClaudeNoGuestPasses)

        assertFalse(passes.isOffered(null))
        assertTrue(passes.isOffered(snapshot(AccountTier.ClaudeMax)))
        assertFalse(passes.isOffered(snapshot(AccountTier.ClaudePro)))
        assertFalse(passes.isOffered(snapshot(AccountTier.ClaudeApi)))
    }

    @Test
    fun `should keep a guest pass once it is fetched`() = runBlocking {
        val pass = GuestPass(passesRemaining = 3, referralURL = "https://claude.ai/referral/abc")
        val passes = GuestPasses(ClaudeGuestPassSource { pass })

        passes.fetch().done()

        assertEquals(pass, passes.pass)
        assertNull(passes.error)
        assertFalse(passes.isFetching)
    }

    @Test
    fun `should keep a failed guest pass fetch apart from usage and let it be dismissed`() = runBlocking {
        answerCLI(usageScreen)
        val passes = GuestPasses(ClaudeGuestPassSource { throw UsageError.ParseFailed("Could not find referral URL") })
        val provider = claude.provider(guestPasses = passes)
        provider.refreshPlain().usage()

        assertTrue(passes.fetch() is Outcome.Refused)

        assertNotNull(passes.error)
        assertNull(provider.defaultAccount.lastError)
        assertSame(passes, provider.defaultAccount.guestPasses)
        passes.clearError()
        assertNull(passes.error)
    }
}

/** A guest-pass source whose CLI is there and answers what [fetch] does. */
internal class ClaudeGuestPassSource(private val fetch: () -> GuestPass) : GuestPassSource {
    override suspend fun isAvailable(): Boolean = true
    override suspend fun fetch(): GuestPass = fetch.invoke()
}
