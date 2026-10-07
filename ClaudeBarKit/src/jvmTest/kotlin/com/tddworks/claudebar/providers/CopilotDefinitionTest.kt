package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.lookup.SecurityResult
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource
import java.net.URI
import java.util.Base64

/**
 * Copilot as data: GitHub's billing API (a fine-grained token and the username it bills) or the
 * Copilot API (a classic token), each read by its own script — the old probes' fixtures, quota
 * for quota.
 */
class CopilotDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** What the last request asked for. */
    private class Seen {
        @Volatile var url: String? = null
        @Volatile var authorization: String? = null
    }

    /** Copilot with its old card's settings where it kept them. */
    private fun make(
        mode: String? = null, body: String? = null, status: Int = 200, username: String? = "octocat",
        limit: String? = null, manual: String? = null, envVar: String? = null,
        vault: MemoryVault = MemoryVault(mapOf("copilot.token" to "saved")), environment: Map<String, String> = emptyMap(),
        ghLogin: String? = null, refuse: Set<String> = emptySet(), seen: Seen = Seen(),
    ): Provider {
        val answer = body ?: if (mode == "copilotAPI") USER else billing()
        val userAnswer = if (mode == "copilotAPI") answer else USER
        val network = StubNetwork { call ->
            seen.url = call.url
            seen.authorization = call.headers.entries.firstOrNull { it.key.equals("Authorization", true) }?.value
            val key = seen.authorization
            when {
                key != null && key in refuse -> Response(401, body = ByteArray(0))
                URI(call.url).path == "/copilot_internal/user" -> Response(status, body = userAnswer.encodeToByteArray())
                else -> Response(status, body = answer.encodeToByteArray())
            }
        }
        val stub = StubbedProvider(network = network).also { stubs += it }
        stub.environment = environment
        // The GitHub CLI's login, as go-keyring stores it.
        stub.security = { arguments ->
            if ("gh:github.com" in arguments && ghLogin != null) {
                SecurityResult(0, "go-keyring-base64:" + Base64.getEncoder().encodeToString(ghLogin.toByteArray()))
            } else {
                SecurityResult(44, "")
            }
        }
        val settings = InMemoryProviderSettings()
        if (mode != null) settings.setDataSourceKind(mode, "copilot")
        settings.setValue(username, "username", "copilot")
        settings.setValue(limit, "monthlyLimit", "copilot")
        settings.setValue(manual, "manualUsage", "copilot")
        settings.setValue(envVar, "authEnvVar", "copilot")
        return stub.make(TestDefinitions.builtIn("copilot"), settings.accounts("copilot"), vault = vault, settings = settings)
    }

    private fun Provider.firstQuota(): UsageQuota {
        val quota = refreshPlain().usage().quotas.firstOrNull()
        assertNotNull(quota)
        return quota!!
    }

    @Test
    fun `should be Copilot, out of the lineup until turned on, with GitHub's Copilot settings as its dashboard`() {
        val provider = make()
        assertEquals("Copilot", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://github.com/settings/copilot/features", provider.plainDashboardURL)
    }

    // Billing API

    @Test
    fun `should show this month's Copilot AI credits against the limit when read from GitHub billing`() {
        val seen = Seen()
        val snapshot = make(seen = seen).refreshPlain().usage()
        val quota = snapshot.quotas.first()
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.TimeLimit("Monthly"), quota.quotaType)
        assertEquals(70.0, quota.percentRemaining)
        assertEquals("15/50 AI credits", quota.resetText)
        assertEquals("octocat", snapshot.accountEmail)
        assertEquals("https://api.github.com/users/octocat/settings/billing/premium_request/usage", seen.url)
        assertEquals("Bearer saved", seen.authorization)
    }

    @Test
    fun `should reset at the end of the calendar month GitHub bills, in UTC`() {
        val quota = make().firstQuota()
        assertEquals(1767225600.0, quota.resetsAtSeconds) // 2026-01-01T00:00Z
        assertEquals(31.0 * 86400, quota.window?.lengthSeconds)
    }

    @Test
    fun `should measure the credits against the person's monthly limit`() {
        val quota = make(limit = "300").firstQuota()
        assertEquals("15/300 AI credits", quota.resetText)
        assertEquals(95.0, quota.percentRemaining)
    }

    @Test
    fun `should keep the monthly limit the old card saved as a number`() {
        assertEquals("300", Setting(id = "monthlyLimit", label = "", kind = Setting.Kind.Text(pattern = "^[1-9][0-9]*$"), default = "50").value("300"))
    }

    @Test
    fun `should show nothing used yet when GitHub bills no Copilot requests`() {
        val quota = make(body = billing("[]")).firstQuota()
        assertEquals(100.0, quota.percentRemaining)
        assertEquals("0/50 AI credits", quota.resetText)
    }

    @ParameterizedTest
    @CsvSource("20, 60.0, 20/50 AI credits (manual)", "40%, 60.0, 20/50 AI credits (manual)")
    fun `should show the usage the person entered when an organization seat bills nothing`(manual: String, left: Double, text: String) {
        val quota = make(body = billing("[]"), manual = manual).firstQuota()
        assertEquals(left, quota.percentRemaining)
        assertEquals(text, quota.resetText)
    }

    @Test
    fun `should show how far over the limit the usage is`() {
        val quota = make(body = billing("[]"), manual = "198%").firstQuota()
        assertEquals(-98.0, quota.percentRemaining)
    }

    @Test
    fun `should show GitHub's own numbers over the usage the person entered`() {
        val quota = make(manual = "40").firstQuota()
        assertEquals("15/50 AI credits", quota.resetText)
    }

    @Test
    fun `should read the Copilot API when billing has no username`() {
        val seen = Seen()
        make(username = null, seen = seen).refreshPlain()
        assertEquals("https://api.github.com/copilot_internal/user", seen.url)
    }

    @Test
    fun `should be unavailable with no username and no token`() {
        assertFalse(make(username = null, vault = MemoryVault()).isPlainAvailable())
    }

    @Test
    fun `should use the token in the environment variable the person named`() {
        val seen = Seen()
        make(envVar = "MY_GH", vault = MemoryVault(), environment = mapOf("MY_GH" to "env"), seen = seen).refreshPlain()
        assertEquals("Bearer env", seen.authorization)
    }

    @Test
    fun `should use COPILOT_TOKEN when the person named no variable`() {
        val seen = Seen()
        make(vault = MemoryVault(), environment = mapOf("COPILOT_TOKEN" to "env"), seen = seen).refreshPlain()
        assertEquals("Bearer env", seen.authorization)
    }

    @Test
    fun `should ask for a new token when GitHub refuses it`() {
        assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), make(status = 401).refreshPlain())
    }

    @Test
    fun `should say the token lacks Plan read access when GitHub forbids billing`() {
        assertEquals(
            RefreshOutcome.Failed(UsageError.ExecutionFailed("Forbidden - ensure the token has 'Plan: read' permission")),
            make(status = 403).refreshPlain(),
        )
    }

    // Copilot API

    @Test
    fun `should show the AI credits, plan and monthly reset from the Copilot API when the person chose it`() {
        val seen = Seen()
        val snapshot = make(mode = "copilotAPI", seen = seen).refreshPlain().usage()
        assertEquals("https://api.github.com/copilot_internal/user", seen.url)
        val quota = snapshot.quotas.first()
        assertEquals(99.3, quota.percentRemaining)
        assertEquals("2/300 AI credits", quota.resetText)
        assertEquals(1772323200.0, quota.resetsAtSeconds) // 2026-03-01T00:00Z
        assertEquals(28.0 * 86400, quota.window?.lengthSeconds)
        // The plan is the account's tier, never its email.
        assertEquals(AccountTier.Custom("business"), snapshot.accountTier)
        assertNull(snapshot.accountEmail)
    }

    @Test
    fun `should show the usage from the Copilot API without a username`() {
        assertEquals(1, make(mode = "copilotAPI", username = null).refreshPlain().usage().quotas.size)
    }

    @ParameterizedTest
    @ValueSource(
        strings = [
            """{"copilot_plan":"enterprise","quota_snapshots":{"premium_interactions":{"unlimited":true}}}""",
            """{"copilot_plan":"free","quota_snapshots":{"chat":{"entitlement":50}}}""",
        ],
    )
    fun `should show no made-up 100% when the plan is unlimited or has no AI-credits quota`(body: String) {
        val product = make(mode = "copilotAPI", body = body)
        val account = product.defaultAccount
        val snapshot: UsageSnapshot = product.refreshNow(account).usage()
        assertTrue(snapshot.quotas.isEmpty())
    }

    @Test
    fun `should read the Copilot API with the GitHub CLI's login when no token is saved`() {
        val seen = Seen()
        val snapshot = make(mode = "copilotAPI", vault = MemoryVault(), ghLogin = "gho_cli", seen = seen).refreshPlain().usage()
        assertEquals("Bearer gho_cli", seen.authorization)
        assertEquals("2/300 AI credits", snapshot.quotas.firstOrNull()?.resetText)
    }

    @Test
    fun `should show the GitHub login and plan the Copilot API names`() {
        val body = """{"login":"octocat","copilot_plan":"individual","quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1487,"percent_remaining":99.1}}}"""
        val snapshot = make(mode = "copilotAPI", body = body).refreshPlain().usage()
        assertEquals("octocat", snapshot.accountEmail)
        assertEquals(AccountTier.Custom("individual"), snapshot.accountTier)
    }

    @Test
    fun `should read the Copilot API with the GitHub CLI's login when billing has no token`() {
        val seen = Seen()
        val snapshot = make(vault = MemoryVault(), ghLogin = "gho_cli", seen = seen).refreshPlain().usage()
        assertEquals("https://api.github.com/copilot_internal/user", seen.url)
        assertEquals("2/300 AI credits", snapshot.quotas.firstOrNull()?.resetText)
    }

    // Accounts

    @Test
    fun `should ask an added login on billing for its token, username and monthly limit`() {
        assertEquals(listOf("token", "username", "monthlyLimit"), make().accounts.form.map { it.id })
    }

    @Test
    fun `should ask an added login on the Copilot API only for its token`() {
        assertEquals(listOf("token"), make(mode = "copilotAPI").accounts.form.map { it.id })
    }

    @Test
    fun `should read an added login with its own token, username and limit, never the environment's token`() {
        val seen = Seen()
        val provider = make(vault = MemoryVault(), environment = mapOf("COPILOT_TOKEN" to "env"), seen = seen)
        val work = provider.accounts.add(filling = mapOf("token" to "work", "username" to "hubot", "monthlyLimit" to "300")).done()
        val quota = provider.refreshNow(work).usage().quotas.first()
        assertEquals("Bearer work", seen.authorization)
        assertEquals("https://api.github.com/users/hubot/settings/billing/premium_request/usage", seen.url)
        assertEquals("15/300 AI credits", quota.resetText)
    }

    private companion object {
        fun billing(items: String = """[{"product":"Copilot","model":"Claude Sonnet 4","grossQuantity":10.0},{"product":"Copilot","model":"GPT-5","grossQuantity":5.0},{"product":"Actions","grossQuantity":99}]"""): String =
            """{"timePeriod":{"year":2025,"month":12},"user":"octocat","usageItems":$items}"""

        const val USER = """{"copilot_plan":"business","quota_snapshots":{"premium_interactions":{"entitlement":300,"percent_remaining":99.3,"remaining":298,"unlimited":false}},"quota_reset_date_utc":"2026-03-01T00:00:00.000Z"}"""
    }
}
