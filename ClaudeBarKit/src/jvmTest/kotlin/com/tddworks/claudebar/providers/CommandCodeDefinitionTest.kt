package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.Arguments
import org.junit.jupiter.params.provider.MethodSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.io.IOException
import java.net.URI
import java.net.URLDecoder

/**
 * Command Code as data: `whoami`, then `credits` with the org it named, read by
 * `commandcode-credits.js` — the old probe's fixtures, quota for quota.
 */
class CommandCodeDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    /** What a request broke of what Command Code expects — checked once each test is done. */
    private val problems = mutableListOf<String>()

    @AfterEach
    fun cleanUp() {
        stubs.forEach { it.cleanUp() }
        assertEquals(emptyList<String>(), problems)
    }

    private fun make(
        json: String = SAMPLE_RESPONSE, whoami: String = """{"user":{"userName":"alice"},"org":{"id":42}}""",
        status: Int = 200, creditsStatus: Int? = null, networkFailure: Boolean = false,
        acceptedTokens: List<String> = listOf("personal", "work", "file"),
        vault: MemoryVault = MemoryVault(mapOf("commandcode.apiKey" to "personal")),
        environment: Map<String, String> = emptyMap(),
        /** What `~/.commandcode/auth.json` holds, when the CLI saved one. */
        authFile: String? = null,
    ): Provider {
        val first = runCatching { Json.parseToJsonElement(whoami) as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())
        val payload = first["data"] as? JsonObject ?: first
        val expectedOrg = ((payload["org"] as? JsonObject)?.get("id") as? JsonPrimitive)?.content
        val network = StubNetwork { call ->
            val url = URI(call.url)
            if (url.host != "api.commandcode.ai") problems += "host ${url.host}"
            if (call.timeoutSeconds != 15.0) problems += "timeout ${call.timeoutSeconds}"
            val authorization = call.headers.entries.firstOrNull { it.key.equals("Authorization", true) }?.value ?: ""
            if (authorization !in acceptedTokens.map { "Bearer $it" }) problems += "authorization $authorization"
            if (networkFailure) throw IOException("The Internet connection appears to be offline.")
            val isWhoami = url.path == "/alpha/whoami"
            if (!isWhoami) {
                val query = url.rawQuery?.split("&")?.map { it.split("=", limit = 2) }
                    ?.firstOrNull { it[0] == "orgId" }?.getOrNull(1)?.let { URLDecoder.decode(it, Charsets.UTF_8) }
                if (query != expectedOrg) problems += "orgId $query, expected $expectedOrg"
            }
            Response(if (isWhoami) status else (creditsStatus ?: status), body = (if (isWhoami) whoami else json).encodeToByteArray())
        }
        val stub = StubbedProvider(network = network).also { stubs += it }
        stub.environment = environment
        if (authFile != null) {
            File(stub.home, ".commandcode").mkdirs()
            File(stub.home, ".commandcode/auth.json").writeText(authFile)
        }
        return stub.make(TestDefinitions.builtIn("commandcode"), vault = vault, settings = InMemoryProviderSettings())
    }

    private fun parse(json: String, accountEmail: String? = null): UsageSnapshot {
        val user = buildJsonObject {
            putJsonObject("user") { put("userName", accountEmail ?: "") }
            putJsonObject("org") { put("id", 42) }
        }
        return make(json, whoami = user.toString()).refreshPlain().usage()
    }

    private fun UsageSnapshot.required(type: QuotaType): UsageQuota {
        val quota = quota(type)
        assertNotNull(quota, "no $type")
        return quota!!
    }

    @Test
    fun `should file the usage under Command Code`() {
        assertEquals("commandcode", parse(SAMPLE_RESPONSE).providerId)
    }

    @Test
    fun `should show the five-hour window as the session, with its reset`() {
        val session = parse(SAMPLE_RESPONSE).required(QuotaType.Session)

        assertEquals(75.0, session.percentRemaining)
        assertEquals(1_770_000_000.0, session.resetsAtSeconds)
        assertEquals(5.0 * 3600, session.windowSeconds)
    }

    @Test
    fun `should show the weekly window with its reset`() {
        val weekly = parse(SAMPLE_RESPONSE).required(QuotaType.Weekly)

        assertEquals(75.0, weekly.percentRemaining)
        assertEquals(1_770_500_000.0, weekly.resetsAtSeconds)
        assertEquals(7.0 * 24 * 3600, weekly.windowSeconds)
    }

    @Test
    fun `should show the plan's credits left in dollars out of its allowance`() {
        val credits = parse(SAMPLE_RESPONSE).required(QuotaType.TimeLimit("Credits"))

        assertEquals(Left.Balance(Money(dollars("8.5")), Money(dollars("10"))), credits.left)
        assertEquals(85.0, credits.percentRemaining) // 8.5 of 10
        assertEquals(dollars("8.5"), credits.dollarRemainingNanos)
        assertEquals(dollars("1.5"), credits.dollarUsedNanos)
        assertEquals(dollars("10"), credits.dollarCapNanos)
    }

    @Test
    fun `should show the account's user name`() {
        val snapshot = parse(SAMPLE_RESPONSE, accountEmail = "alice@example.com")

        assertEquals("alice@example.com", snapshot.accountEmail)
    }

    @Test
    fun `should show the usage when Command Code wraps it in a data envelope`() {
        val json = """
        { "data": $SAMPLE_RESPONSE }
        """

        val snapshot = parse(json)

        assertEquals(75.0, snapshot.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(dollars("8.5"), snapshot.quota(QuotaType.TimeLimit("Credits"))?.dollarRemainingNanos)
    }

    @Test
    fun `should show no quotas when Command Code reports nothing`() {
        assertTrue(parse("{}").quotas.isEmpty())
    }

    @Test
    fun `should fail when Command Code answers with something that isn't JSON`() {
        assertTrue(make("not json", whoami = WHOAMI_42).refreshPlain() is RefreshOutcome.Failed)
    }

    @Test
    fun `should show no window whose cap is zero`() {
        val json = """
        {
          "windowLimits": {
            "fiveHour": { "used": 0, "cap": 0, "resetAt": 1770000000000 },
            "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
          }
        }
        """

        val snapshot = parse(json)

        assertNull(snapshot.quota(QuotaType.Session))
        assertEquals(75.0, snapshot.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should show a window full when Command Code omits how much is used`() {
        val json = """
        { "windowLimits": { "fiveHour": { "cap": 40, "resetAt": 1770000000000 } } }
        """

        assertEquals(100.0, parse(json).quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should know the reset when it is a date string`() {
        val json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": "2026-09-11T12:00:00Z" } } }
        """

        val session = parse(json).required(QuotaType.Session)

        assertEquals(1_789_128_000.0, session.resetsAtSeconds)
    }

    @Test
    fun `should know the reset when it is in seconds`() {
        val json = """
        { "windowLimits": { "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000 } } }
        """

        val session = parse(json).required(QuotaType.Session)

        assertEquals(1_770_000_000.0, session.resetsAtSeconds)
    }

    @Test
    fun `should size the credits by the most specific plan name`() {
        // individual-pro-v1 ($80) must not match individual-pro ($30)
        val json = """
        { "credits": { "monthlyCredits": 80, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-pro-v1" } }
        """

        val credits = parse(json).required(QuotaType.TimeLimit("Credits"))

        assertEquals(100.0, credits.percentRemaining)
        assertEquals(dollars("80"), credits.dollarCapNanos)
    }

    @Test
    fun `should recognise a plan whatever its case or underscores`() {
        val json = """
        { "credits": { "monthlyCredits": 4, "purchasedCredits": 0, "freeCredits": 0, "planId": "Teams_Pro" } }
        """

        val credits = parse(json).required(QuotaType.TimeLimit("Credits"))

        assertEquals(10.0, credits.percentRemaining) // 4 of 40
        assertEquals(dollars("40"), credits.dollarCapNanos)
    }

    @Test
    fun `should add purchased and free credits to the plan's allowance`() {
        val json = """
        {
          "credits": {
            "monthlyCredits": 2, "purchasedCredits": 20, "freeCredits": 3, "planId": "individual-go"
          }
        }
        """

        val credits = parse(json).required(QuotaType.TimeLimit("Credits"))

        assertEquals(dollars("25"), credits.dollarRemainingNanos)
        assertEquals(dollars("33"), credits.dollarCapNanos) // plan 10 + purchased 20 + free 3
    }

    @Test
    fun `should show only the dollars left, with no percentage, for an unknown plan with no windows`() {
        val json = """
        { "credits": { "monthlyCredits": 12.5, "purchasedCredits": 0, "freeCredits": 0, "planId": "mystery-tier" } }
        """

        val credits = parse(json).required(QuotaType.TimeLimit("Credits"))

        // A balance with no ceiling is money only — no percentage (the Left law).
        assertEquals(Left.Balance(Money(dollars("12.5")), null), credits.left)
        assertNull(credits.percentLeft)
        assertEquals(dollars("12.5"), credits.dollarRemainingNanos)
        assertNull(credits.dollarCapNanos)
    }

    @Test
    fun `should show no balance meter when windows already report usage`() {
        val json = """
        {
          "credits": { "monthlyCredits": 12.5, "planId": "mystery-tier" },
          "windowLimits": { "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 } }
        }
        """

        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertNotNull(snapshot.quota(QuotaType.Weekly))
    }

    @Test
    fun `should show no credits left when the plan's allowance is spent`() {
        val json = """
        { "credits": { "monthlyCredits": 0, "purchasedCredits": 0, "freeCredits": 0, "planId": "individual-go" } }
        """

        val snapshot = parse(json)

        assertEquals(0.0, snapshot.quota(QuotaType.TimeLimit("Credits"))?.percentRemaining)
    }

    @Test
    fun `should show a window past its cap as below zero`() {
        val json = """
        { "windowLimits": { "fiveHour": { "used": 44, "cap": 40, "resetAt": 1770000000000 } } }
        """

        assertEquals(-10.0, parse(json).quota(QuotaType.Session)?.percentRemaining)
    }

    @Test
    fun `should read an added login with its own key, never the environment's`() {
        val vault = MemoryVault(mapOf("commandcode.apiKey" to "personal"))
        val provider = make(vault = vault, environment = mapOf("COMMAND_CODE_API_KEY" to "personal"))
        val work = provider.accounts.add(filling = mapOf("apiKey" to "work")).done()
        assertTrue(work.isEnabled)
        assertEquals("alice", provider.refreshNow(work).usage().accountEmail)
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), provider.refreshNow(work))
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again with cmd login when the key is refused`(status: Int) {
        assertEquals(
            RefreshOutcome.Failed(UsageError.SessionExpired("Run `cmd login` or set COMMAND_CODE_API_KEY.")),
            make(status = status).refreshPlain(),
        )
    }

    @Test
    fun `should read the key the Command Code CLI saved`() {
        assertEquals(3, make(vault = MemoryVault(), authFile = """{"apiKey":"file"}""").refreshPlain().usage().quotas.size)
    }

    @ParameterizedTest
    @ValueSource(strings = ["{}", """{"data":{"user":{"name":"Alice"},"org":{"id":"team & org"}}}"""])
    fun `should show the credits when the account names no organization or a wrapped one`(whoami: String) {
        assertEquals(3, make(whoami = whoami).refreshPlain().usage().quotas.size)
    }

    @ParameterizedTest
    @MethodSource("keys")
    fun `should prefer an environment key over the CLI's saved key, and be unavailable without a usable key`(
        file: String, environment: Map<String, String>, available: Boolean,
    ) {
        val token = environment["COMMAND_CODE_API_KEY"] ?: environment["COMMANDCODE_API_KEY"] ?: "file"
        val provider = make(
            acceptedTokens = listOf(token), vault = MemoryVault(), environment = environment,
            authFile = file.takeIf { it.isNotEmpty() },
        )
        assertEquals(available, provider.isPlainAvailable())
        if (available) {
            assertEquals(3, provider.refreshPlain().usage().quotas.size)
        } else {
            assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), provider.refreshPlain())
        }
    }

    @Test
    fun `should start as Command Code, run by cmd, with its usage dashboard and nothing read yet`() {
        val providerProduct = make()
        val provider = providerProduct.defaultAccount
        assertEquals("commandcode", provider.id)
        assertEquals("Command Code", providerProduct.lineupName(provider))
        assertEquals("cmd", provider.cliCommand)
        assertEquals("https://commandcode.ai/usage", providerProduct.dashboardURL(provider))
        assertTrue(provider.isEnabled)
        assertNull(provider.snapshot)
        assertNull(provider.lastError)
        assertFalse(provider.isSyncing)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403, 500])
    fun `should fail, not show the account alone, when the credits request is refused or errors`(status: Int) {
        val error: UsageError = if (status in listOf(401, 403)) {
            UsageError.SessionExpired("Run `cmd login` or set COMMAND_CODE_API_KEY.")
        } else {
            UsageError.ExecutionFailed("HTTP error: $status")
        }
        val product = make(creditsStatus = status)
        val account = product.defaultAccount
        assertEquals(RefreshOutcome.Failed(error), product.refreshNow(account))
        assertNull(account.snapshot)
        assertEquals(error, account.lastError)
    }

    @Test
    fun `should say it is rate limited, not an HTTP error, when the credits request is`() {
        val product = make(creditsStatus = 429)
        val account = product.defaultAccount
        val outcome = product.refreshNow(account)
        assertEquals("rateLimited", (outcome as? RefreshOutcome.Failed)?.error?.tag)
        assertNull(account.snapshot)
    }

    @Test
    fun `should show no usage when the network fails`() {
        val product = make(networkFailure = true)
        val account = product.defaultAccount
        assertTrue(product.refreshNow(account) is RefreshOutcome.Failed)
        assertNull(account.snapshot)
    }

    @ParameterizedTest
    @ValueSource(strings = ["[]", "not JSON"])
    fun `should fail when either answer is not a JSON object`(body: String) {
        val notJSON = RefreshOutcome.Failed(UsageError.ParseFailed("Failed to parse Command Code response as JSON"))
        assertEquals(notJSON, make(body).refreshPlain())
        assertEquals(notJSON, make(whoami = body).refreshPlain())
    }

    companion object {
        /** Real credits body from `GET /alpha/billing/credits`. */
        private const val SAMPLE_RESPONSE = """
        {
          "credits": {
            "monthlyCredits": 8.5,
            "purchasedCredits": 0,
            "freeCredits": 0,
            "planId": "individual-go"
          },
          "windowLimits": {
            "fiveHour": { "used": 10, "cap": 40, "resetAt": 1770000000000 },
            "weekly": { "used": 50, "cap": 200, "resetAt": 1770500000000 }
          }
        }
        """

        private const val WHOAMI_42 = """{"user":{"userName":""},"org":{"id":42}}"""

        private fun dollars(amount: String): Long = java.math.BigDecimal(amount).movePointRight(9).longValueExact()

        @JvmStatic
        fun keys(): List<Arguments> = listOf(
            Arguments.of("""{"apiKey":"file"}""", mapOf("COMMAND_CODE_API_KEY" to "personal", "COMMANDCODE_API_KEY" to "work"), true),
            Arguments.of("""{"apiKey":"file"}""", mapOf("COMMANDCODE_API_KEY" to "work"), true),
            Arguments.of("{\"apiKey\":\"  file\\n\"}", emptyMap<String, String>(), true),
            Arguments.of("""{"apiKey":"   "}""", emptyMap<String, String>(), false),
            Arguments.of("""["file"]""", emptyMap<String, String>(), false),
            Arguments.of("not JSON", emptyMap<String, String>(), false),
            Arguments.of("", emptyMap<String, String>(), false),
        )
    }
}
