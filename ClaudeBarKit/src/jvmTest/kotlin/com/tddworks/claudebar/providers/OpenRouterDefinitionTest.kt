package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.math.BigDecimal
import java.math.RoundingMode

/** OpenRouter as data: the credits balance is the lifetime credit minus the usage, money with no ceiling; the key and its environment variable are settings. */
class OpenRouterDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun make(
        body: String = """{"data":{"total_credits":"10.00","total_usage":"3.50"}}""", status: Int = 200,
        environment: Map<String, String> = emptyMap(), vault: MemoryVault = MemoryVault(mapOf("openrouter.apiKey" to "personal")),
        settings: InMemoryProviderSettings? = null, replies: Map<String, String>? = null,
    ): Provider {
        val stub = StubbedProvider().also { stubs += it }
        stub.http.answer = answer@{ call ->
            if (call.url != "https://openrouter.ai/api/v1/credits" || call.timeoutSeconds != 30.0 || call.headers["Accept"] != "application/json") {
                return@answer Response(400, body = ByteArray(0))
            }
            if (replies != null) {
                val reply = replies[call.headers["Authorization"] ?: ""] ?: return@answer Response(401, body = ByteArray(0))
                return@answer Response(200, body = reply.encodeToByteArray())
            }
            Response(status, body = body.encodeToByteArray())
        }
        stub.environment = environment
        val repository = settings ?: stub.settings
        return stub.make(TestDefinitions.builtIn("openrouter"), accounts = repository.accounts("openrouter"), vault = vault, settings = repository)
    }

    private fun usd(amount: String) = Money(BigDecimal(amount).movePointRight(9).longValueExact(), "USD")

    /** A report whose credit minus usage is [remaining], with the rest used. */
    private fun report(remaining: String): String {
        val used = BigDecimal("10.00") - BigDecimal(remaining)
        return """{"data":{"total_credits":"10.00","total_usage":"${used.toPlainString()}"}}"""
    }

    /** The mapping script's `usd`: exact money rounded to cents, half up. */
    private fun cents(amount: BigDecimal): String = amount.setScale(2, RoundingMode.HALF_UP).toPlainString()

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show OpenRouter with its credits dashboard and status page, off until turned on`() {
        val provider = make()
        assertEquals("openrouter", provider.id)
        assertEquals("OpenRouter", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://openrouter.ai/credits", provider.definition.profile.links.dashboard)
        assertEquals("https://status.openrouter.ai", provider.definition.profile.links.status)
        assertEquals("OpenRouterIcon", provider.definition.profile.look.icon)
        assertEquals("arrow.triangle.branch", provider.definition.profile.look.symbol)
        assertEquals(listOf(AddAccountWay.FORM), provider.definition.accounts?.ways)
    }

    @ParameterizedTest
    @ValueSource(strings = ["6.50", "0", "1245.67", "-1.25", "0.005"])
    fun `should show the credits left after usage as exact dollars, with no ceiling, no percentage and no window`(remaining: String) {
        val usage = make(body = report(remaining)).refreshPlain().usage()
        val quota = usage.quotas.first()
        assertEquals(1, usage.quotas.size)
        assertEquals(QuotaType.ModelSpecific("Credits"), quota.quotaType)
        assertEquals(Left.Balance(usd(remaining), null), quota.left)
        assertNull(quota.percentLeft)
        assertNull(quota.window)
        val used = BigDecimal("10.00") - BigDecimal(remaining)
        assertEquals("Total: \$${cents(BigDecimal("10.00"))} · Used: \$${cents(used)}", quota.resetText)
    }

    @Test
    fun `should show the credits left when OpenRouter reports amounts as numbers`() {
        val numbers = make(body = """{"data":{"total_credits":10,"total_usage":3.5}}""").refreshPlain().usage()
        assertEquals(Left.Balance(usd("6.5"), null), numbers.quotas.first().left)
    }

    @ParameterizedTest
    @ValueSource(strings = ["0", "-1.25"])
    fun `should show the credits depleted, with no percentage, when they are spent or overdrawn`(remaining: String) {
        val usage = make(body = report(remaining)).refreshPlain().usage()
        assertEquals(QuotaStatus.DEPLETED, usage.quotas.first().status)
        assertNull(usage.quotas.first().percentLeft)
    }

    @ParameterizedTest
    @ValueSource(
        strings = [
            "not JSON", "{}", """{"data":{}}""", """{"data":{"total_credits":"10"}}""",
            """{"data":{"total_credits":"abc","total_usage":"1"}}""", """{"data":{"total_credits":"10","total_usage":"0x1"}}""",
            """{"data":[1]}""", """{"data":null}""",
        ],
    )
    fun `should fail at reading the answer when OpenRouter reports no readable credits`(body: String) {
        val product = make(body = body)
        product.refreshPlain().failure()
        assertEquals(DataSourceError.Step.MAPPING, product.defaultAccount.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when OpenRouter refuses the key`(status: Int) {
        assertEquals(UsageError.AuthenticationRequired, make(status = status).refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(ints = [429, 500])
    fun `should fail at fetching when OpenRouter is rate-limiting or down`(status: Int) {
        val product = make(status = status)
        product.refreshPlain().failure()
        assertEquals(DataSourceError.Step.FETCH, product.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should be unavailable and ask for a key when none is saved or set`() {
        val product = make(vault = MemoryVault())
        assertFalse(product.isPlainAvailable())
        assertEquals(UsageError.AuthenticationRequired, product.refreshPlain().failure())
        assertEquals(DataSourceError.Step.LOOKUP, product.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should use the environment key for the default login and each added login's own saved key`() {
        val vault = MemoryVault(mapOf("openrouter.apiKey" to "personal"))
        val settings = InMemoryProviderSettings()
        val provider = make(
            environment = mapOf("OPENROUTER_API_KEY" to "environment"), vault = vault, settings = settings,
            replies = mapOf(
                "Bearer environment" to """{"data":{"total_credits":"40","total_usage":"0"}}""",
                "Bearer work" to """{"data":{"total_credits":"7.50","total_usage":"0"}}""",
            ),
        )
        val work = provider.accounts.add(filling = mapOf("apiKey" to "work")).done()
        assertTrue(work.isEnabled)
        assertEquals(usd("40").amountNanos, provider.refreshPlain().usage().quotas.first().dollarRemainingNanos)
        assertEquals(usd("7.50").amountNanos, provider.refreshNow(work).usage().quotas.first().dollarRemainingNanos)
        assertNull(settings.accounts(provider.id).first().probeConfig["apiKey"])
        assertEquals("work", vault.secrets["${work.id}.apiKey"])
    }

    @Test
    fun `should use the key from the environment variable the person named`() {
        val replies = mapOf(
            "Bearer named" to """{"data":{"total_credits":"40","total_usage":"0"}}""",
            "Bearer default" to """{"data":{"total_credits":"1","total_usage":"0"}}""",
        )
        val settings = InMemoryProviderSettings()
        settings.setValue("ROUTER_KEY", "authEnvVar", "openrouter")
        val provider = make(environment = mapOf("OPENROUTER_API_KEY" to "default", "ROUTER_KEY" to "named"), settings = settings, replies = replies)
        assertEquals(usd("40").amountNanos, provider.refreshPlain().usage().quotas.first().dollarRemainingNanos)
    }
}
