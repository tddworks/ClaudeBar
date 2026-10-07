package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.AccountTier
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant

/**
 * `codex.json`, run through the real `Provider` and `DataSource` over stubbed connections. The
 * fixtures are the ones the old `CodexUsageProbe`, `CodexAPIUsageProbe` and `DefaultCodexRPCClient`
 * tests used: the definition must give the same usage they gave.
 */
class CodexDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    private fun stub(dataSourceKind: String? = null) = StubbedProvider("codex", dataSourceKind).also { stubs += it }

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    // The definition

    @Test
    fun `should offer Codex over RPC first, then the API, with a hidden terminal fallback and OpenAI's usage dashboard`() {
        val codex = TestDefinitions.builtIn("codex")

        assertEquals("codex", codex.id)
        assertEquals("Codex", codex.profile.name)
        assertEquals("codex", codex.cli)
        assertEquals(listOf("rpc", "api", "tty"), codex.dataSources.map { it.kind })
        assertEquals("rpc", codex.defaultDataSource)
        assertEquals("tty", codex.dataSource("rpc")?.fallback?.to)
        assertEquals(true, codex.dataSource("tty")?.hidden)
        assertEquals("https://platform.openai.com/usage", codex.profile.links.dashboard)
    }

    @Test
    fun `should read Codex over RPC until the person picks the API`() {
        val rpc = stub()
        val api = stub("api")

        assertEquals("rpc", rpc.makeProvider("codex").configuration.activeKind)
        assertEquals("api", api.makeProvider("codex").configuration.activeKind)
    }

    // RPC

    @Test
    fun `should show the session and weekly windows with their resets when Codex answers over RPC`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000,"windowDurationMins":300},"secondary":{"usedPercent":50,"resetsAt":1735500000}}}}""")
        val codex = stub.makeProvider("codex")

        val usage = codex.refreshPlain().usage()

        assertEquals("codex", usage.providerId)
        assertEquals(70.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(1735000000.0, usage.quota(QuotaType.Session)?.resetsAtSeconds)
        assertEquals(300.0 * 60, usage.quota(QuotaType.Session)?.windowSeconds)
        assertEquals(50.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals("rpc", codex.defaultAccount.answeredBy)
        assertNull(codex.defaultAccount.lastError)
    }

    @Test
    fun `should show a free plan's session full, labelled Free plan`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"planType":"free"}}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(1, usage.quotas.size)
        assertEquals(100.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals("Free plan", usage.quota(QuotaType.Session)?.resetText)
    }

    @Test
    fun `should show Spark's windows after the session and weekly ones`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000},"secondary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30,"resetsAt":1735000000}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark","primary":{"usedPercent":40,"resetsAt":1735100000},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(4, usage.quotas.size)
        assertEquals(QuotaType.Session, usage.quotas[0].quotaType)
        assertEquals(QuotaType.TimeLimit("Spark"), usage.quotas[2].quotaType)
        assertEquals(60.0, usage.quotas[2].percentRemaining)
        assertEquals(QuotaType.TimeLimit("Spark 7d"), usage.quotas[3].quotaType)
        assertEquals(80.0, usage.quotas[3].percentRemaining)
        assertEquals(10080.0 * 60, usage.quotas[3].windowSeconds)
    }

    @Test
    fun `should show neither the main bucket twice nor buckets that have no window`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark"},"codex_other":{"limitId":"codex_other","limitName":"Other","primary":{"usedPercent":5}}}}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(listOf(QuotaType.Session, QuotaType.TimeLimit("Other")), usage.quotas.map { it.quotaType })
        assertEquals(95.0, usage.quotas[1].percentRemaining)
    }

    @Test
    fun `should show the terminal's windows, answered by Terminal, when RPC fails`() {
        val stub = stub()
        stub.answerRPC("""{"id":2,"error":{"message":"Authentication required"}}""")
        stub.answerTerminal(
            """
            Account: someone@example.com
            5h limit:  [██████░░░░] 80% left (resets 14:00)
            Weekly limit: [███░░░░░░] 35% left
            """.trimIndent(),
        )
        val codex = stub.makeProvider("codex")

        val usage = codex.refreshPlain().usage()

        assertEquals(80.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(35.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals("tty", codex.defaultAccount.answeredBy)
        assertEquals("Terminal", codex.defaultAccount.answeredByLabel)
    }

    @Test
    fun `should report the RPC failure and keep the last usage when RPC and the terminal both fail`() {
        val stub = stub()
        // First refresh: initialize, usage, the account. Second: initialize, then an RPC error.
        stub.answerRPC("""{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}}}}""")
        stub.cli.located = { "/usr/local/bin/$it" }
        stub.cli.answer = { throw UsageError.ExecutionFailed("TTY not available") }
        val codex = stub.makeProvider("codex")
        val first = codex.refreshPlain().usage()
        stub.answerRPC("""{"id":2,"error":{"message":"Authentication required"}}""")

        assertTrue(codex.refreshPlain() is RefreshOutcome.Failed)

        assertEquals(UsageError.ExecutionFailed("RPC error: Authentication required"), codex.defaultAccount.lastError)
        assertEquals(DataSourceError.Step.FETCH, codex.defaultAccount.lastFailedStep)
        assertEquals(first, codex.defaultAccount.snapshot)
    }

    // Terminal

    @Test
    fun `should ask to sign in when the terminal says Codex is not logged in`() {
        val stub = stub("tty")
        stub.answerTerminal("Error: Not logged in. Please log in with `codex login`.")
        val codex = stub.makeProvider("codex")

        assertEquals(UsageError.AuthenticationRequired, codex.refreshPlain().failure())
        assertEquals(DataSourceError.Step.MAPPING, codex.defaultAccount.lastFailedStep)
    }

    // API

    @Test
    fun `should show the usage the API's headers report over its body`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP(
            """{"rate_limit":{"primary_window":{"reset_after_seconds":3600}}}""",
            headers = mapOf("x-codex-primary-used-percent" to "25.5", "x-codex-secondary-used-percent" to "40"),
        )

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(74.5, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(60.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertNotNull(usage.quota(QuotaType.Session)?.resetsAtSeconds)
    }

    @Test
    fun `should show the usage in the API's body when it sends no usage headers`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":15.0,"reset_at":1735000000},"secondary_window":{"used_percent":45.0}}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(85.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(1735000000.0, usage.quota(QuotaType.Session)?.resetsAtSeconds)
        assertEquals(55.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should show Spark's windows after the session and weekly ones when read through the API`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"used_percent":20}},"additional_rate_limits":[{"limit_name":"codex_spark","rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000},"secondary_window":{"used_percent":40}}}]}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(
            listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.TimeLimit("Spark"), QuotaType.TimeLimit("Spark 7d")),
            usage.quotas.map { it.quotaType },
        )
        assertEquals(70.0, usage.quotas[2].percentRemaining)
        assertEquals(18000.0, usage.quotas[2].windowSeconds)
        assertEquals(60.0, usage.quotas[3].percentRemaining)
    }

    @Test
    fun `should show the plan and the credits spent from the balance`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP(
            """{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10}},"credits":{"has_credits":true,"balance":"900"}}""",
            headers = mapOf("x-codex-credits-balance" to "750"),
        )

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(AccountTier.Custom("PLUS"), usage.accountTier)
        assertEquals(250 * NANOS, usage.costUsage?.totalCostNanos)
        assertEquals(1000 * NANOS, usage.costUsage?.budgetNanos)
    }

    // https://github.com/tddworks/ClaudeBar/issues/444
    @Test
    fun `should show no cost when the account has no credits (#444)`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP("""{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800}},"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertNull(usage.costUsage)
    }

    @Test
    fun `should show no quotas, not a failure, when the API reports nothing`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP("{}")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should be unavailable and ask to sign in when there is no Codex login for the API`() {
        val stub = stub("api")
        val codex = stub.makeProvider("codex")

        assertFalse(codex.isPlainAvailable())
        assertEquals(UsageError.AuthenticationRequired, codex.refreshPlain().failure())
        assertEquals(DataSourceError.Step.LOOKUP, codex.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should ask to sign in again when the API refuses the login`() {
        val stub = stub("api")
        stub.writeCodexAuth()
        stub.answerHTTP("", status = 401)
        val codex = stub.makeProvider("codex")

        assertEquals(UsageError.SessionExpired(), codex.refreshPlain().failure())
    }

    @Test
    fun `should renew an old login and save the new tokens back to Codex's file`() {
        val stub = stub("api")
        stub.writeCodexAuth(token = "old-token", accountId = "acct-1", lastRefresh = Instant.now().minusSeconds(9 * 86400))
        stub.http.answer = { call ->
            if (call.url.contains("oauth/token")) {
                Response(200, body = """{"access_token":"new-token","refresh_token":"new-refresh-token"}""".encodeToByteArray())
            } else {
                val authorized = call.headers.entries.firstOrNull { it.key.equals("Authorization", true) }?.value == "Bearer new-token"
                Response(if (authorized) 200 else 401, body = """{"rate_limit":{"primary_window":{"used_percent":10.0}}}""".encodeToByteArray())
            }
        }

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals(90.0, usage.quota(QuotaType.Session)?.percentRemaining)
        val tokens = readCodexAuth(stub)["tokens"] as? JsonObject
        assertEquals("new-token", (tokens?.get("access_token") as? JsonPrimitive)?.content)
        assertEquals("new-refresh-token", (tokens?.get("refresh_token") as? JsonPrimitive)?.content)
        assertEquals("acct-1", (tokens?.get("account_id") as? JsonPrimitive)?.content)
    }

    @Test
    fun `should ask to sign in again when the saved login can no longer be renewed`() {
        val stub = stub("api")
        stub.writeCodexAuth(lastRefresh = Instant.now().minusSeconds(9 * 86400))
        stub.answerHTTP("""{"error":{"code":"refresh_token_expired"}}""", status = 400)
        val codex = stub.makeProvider("codex")

        assertEquals(UsageError.SessionExpired(), codex.refreshPlain().failure())
        assertEquals(DataSourceError.Step.LOOKUP, codex.defaultAccount.lastFailedStep)
    }

    private fun readCodexAuth(stub: StubbedProvider): JsonObject =
        Json.parseToJsonElement(File(stub.home, ".codex/auth.json").readText()) as JsonObject

    private companion object {
        const val NANOS = 1_000_000_000L
    }
}

/** Why a refresh failed; fails the test when it showed usage. */
private fun RefreshOutcome.failure(): UsageError {
    assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
    return (this as RefreshOutcome.Failed).error
}
