package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.lookup.FakeStorage
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.time.Instant
import kotlin.math.abs

/**
 * Devin as data: the organization's daily and weekly quota from `app.devin.ai`, with the
 * browser's sign-in, or a pasted session token and organization ID, read by `devin-quota.js`.
 */
class DevinDefinitionTest {
    private val quota = """{"is_quota_plan":true,"has_quota_allocation":true,"daily_percentage":0.12,"weekly_percentage":42,"daily_reset_at":"2026-06-11T00:00:00-08:00","weekly_reset_at":"2026-06-14T00:00:00-08:00","hide_daily_quota":false}"""

    private class Seen {
        @Volatile var last: HttpCall? = null
    }

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    private fun organization(id: String): InMemoryProviderSettings = InMemoryProviderSettings().apply { setValue(id, "organization", "devin") }

    private fun make(
        body: String = quota, status: Int = 200, environment: Map<String, String> = emptyMap(),
        vault: MemoryVault = MemoryVault(mapOf("devin.token" to "auth1_pasted-session-token")),
        settings: InMemoryProviderSettings = organization("org_abc123"),
        browser: List<Map<String, String>> = emptyList(), seen: Seen = Seen(),
    ): Provider {
        val definition = TestDefinitions.builtIn("devin")
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                seen.last = call
                if (call.method != "GET" || call.header("Accept") != "application/json") return Response(400, body = ByteArray(0))
                return Response(status, body = body.encodeToByteArray())
            }
        }
        val connections = testDataSources(network = network, environment = environment, browserStorage = FakeStorage(browser))
        return Provider(
            definition = definition, settings = settings, saved = settings.accounts(definition.id),
            makeDataSource = { source, login -> connections.make(source, definition.id, vault.scoped(login), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    private fun seconds(iso: String) = Instant.parse(iso).epochSecond.toDouble()

    @Test
    fun `should be Devin, off until turned on, with its dashboard and icon`() {
        val devin = make()
        assertEquals("devin", devin.id)
        assertEquals("Devin", devin.name)
        assertEquals(false, devin.plainIsInLineup)
        assertEquals("https://app.devin.ai/settings/usage", devin.definition.profile.links.dashboard)
        assertEquals("DevinIcon", devin.definition.profile.look.icon)
    }

    @Test
    fun `should ask for the organization's quota with the pasted token`() {
        val seen = Seen()
        make(seen = seen).refreshPlain()
        val request = seen.last
        assertNotNull(request)
        assertEquals("https://app.devin.ai/api/org_abc123/billing/quota/usage", request!!.url)
        assertEquals("Bearer auth1_pasted-session-token", request.header("Authorization"))
        assertEquals("org_abc123", request.header("x-cog-org-id"))
    }

    @Test
    fun `should show the daily and weekly quota, reading a fraction as a percentage`() {
        val usage = make().refreshPlain().usage()
        val daily = usage.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Daily") }
        assertNotNull(daily)
        assertTrue(abs(daily!!.percentRemaining - 88) < 0.0001, "${daily.percentRemaining}")
        assertEquals(seconds("2026-06-11T08:00:00Z"), daily.resetsAtSeconds)
        val weekly = usage.quota(QuotaType.Weekly)
        assertNotNull(weekly)
        assertEquals(58.0, weekly!!.percentRemaining)
        assertEquals(seconds("2026-06-14T08:00:00Z"), weekly.resetsAtSeconds)
    }

    @Test
    fun `should leave out the daily quota when Devin hides it`() {
        val body = """{"daily_percentage":10,"weekly_percentage":42,"hide_daily_quota":true}"""
        assertEquals(listOf(QuotaType.Weekly), make(body = body).refreshPlain().usage().quotas.map { it.quotaType })
    }

    @Test
    fun `should read the nested quota answer, its plan and the extra usage balance`() {
        val body = """{"plan_name":"pro","overage_balance":70.87,"quota_usage":{"daily_quota":{"used":3,"limit":10,"reset_at":"2026-06-01T08:00:00Z"},"weekly_quota":{"remaining_percent":0.25,"next_reset_at":1780560000}}}"""
        val usage = make(body = body).refreshPlain().usage()
        assertEquals(70.0, usage.quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("Daily") }?.percentRemaining)
        assertEquals(25.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(1780560000.0, usage.quota(QuotaType.Weekly)?.resetsAtSeconds)
        assertEquals(AccountTier.Custom("Pro"), usage.accountTier)
        val extra = usage.quotas.firstOrNull { it.quotaType == QuotaType.ModelSpecific("Extra usage") }
        assertNotNull(extra)
        assertEquals(Left.Balance(Money(70_870_000_000, "USD"), null), extra!!.left)
    }

    @Test
    fun `should use the token from the environment before the pasted one`() {
        val seen = Seen()
        make(environment = mapOf("DEVIN_BEARER_TOKEN" to "auth1_environment"), seen = seen).refreshPlain()
        assertEquals("Bearer auth1_environment", seen.last?.header("Authorization"))
    }

    @Test
    fun `should ask for a token when there is none`() {
        val devin = make(vault = MemoryVault())
        val account = devin.defaultAccount
        assertEquals(UsageError.AuthenticationRequired, devin.refreshNow(account).failure())
        assertEquals(DataSourceError.Step.LOOKUP, account.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask for a new token when Devin refuses it`(status: Int) {
        val devin = make(status = status)
        val error = devin.refreshNow(devin.defaultAccount).failure()
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals("Sign in to app.devin.ai again, or paste a new session token.", (error as UsageError.SessionExpired).hint)
    }

    @Test
    fun `should fail reading the quota when Devin's answer has no daily or weekly window`() {
        val devin = make(body = """{"is_quota_plan":false}""")
        val account = devin.defaultAccount
        devin.refreshNow(account).failure()
        assertEquals(DataSourceError.Step.MAPPING, account.lastFailedStep)
    }

    // The browser's sign-in

    private val signedIn = mapOf(
        "persist:auth1_session" to """{"token":"auth1_browser"}""",
        "last-internal-org-for-external-org-v1-acme" to """"org_browser"""",
    )

    @Test
    fun `should use the app_devin_ai sign-in in the browser before anything pasted`() {
        val seen = Seen()
        make(environment = mapOf("DEVIN_BEARER_TOKEN" to "auth1_environment"), browser = listOf(signedIn), seen = seen).refreshPlain()
        val request = seen.last
        assertNotNull(request)
        assertEquals("https://app.devin.ai/api/org_browser/billing/quota/usage", request!!.url)
        assertEquals("Bearer auth1_browser", request.header("Authorization"))
        assertEquals("org_browser", request.header("x-cog-org-id"))
    }

    @Test
    fun `should use the pasted token with the pasted organization when the browser has no sign-in`() {
        val seen = Seen()
        make(browser = listOf(mapOf("unrelated" to "x")), seen = seen).refreshPlain()
        assertEquals("https://app.devin.ai/api/org_abc123/billing/quota/usage", seen.last?.url)
        assertEquals("Bearer auth1_pasted-session-token", seen.last?.header("Authorization"))
    }

    @Test
    fun `should list the browser first in the key lookup order`() {
        val lookup = make().definition.dataSources.firstOrNull()?.credential
        assertNotNull(lookup)
        assertEquals(listOf("Browser storage · app.devin.ai", "\$DEVIN_BEARER_TOKEN", "API key saved in ClaudeBar"), lookup!!.lookupOrder)
    }

    @Test
    fun `should read an added login only with its own pasted token, never the browser's`() {
        val settings = organization("org_abc123")
        val vault = MemoryVault(mapOf("devin.token" to "auth1_pasted-session-token"))
        val seen = Seen()
        val devin = make(vault = vault, settings = settings, browser = listOf(signedIn), seen = seen)
        val work = devin.accounts.add(mapOf("token" to "auth1_work", "organization" to "org_work")).done()
        devin.refreshNow(work)
        assertEquals("https://app.devin.ai/api/org_work/billing/quota/usage", seen.last?.url)
        assertEquals("Bearer auth1_work", seen.last?.header("Authorization"))
    }
}
