package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
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

/** Vercel AI Gateway as data: the credits balance is money with no ceiling; the key and its environment variable are settings. */
class VercelDefinitionTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun make(
        body: String = """{"balance":95.50,"total_used":4.50}""", status: Int = 200,
        environment: Map<String, String> = emptyMap(), vault: MemoryVault = MemoryVault(mapOf("vercel-gateway.apiKey" to "personal")),
        settings: InMemoryProviderSettings? = null, replies: Map<String, String>? = null,
    ): Provider {
        val stub = StubbedProvider().also { stubs += it }
        stub.http.answer = answer@{ call ->
            if (call.url != "https://ai-gateway.vercel.sh/v1/credits" || call.timeoutSeconds != 30.0 || call.headers["Accept"] != "application/json") {
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
        return stub.make(TestDefinitions.builtIn("vercel-gateway"), accounts = repository.accounts("vercel-gateway"), vault = vault, settings = repository)
    }

    private fun usd(amount: String) = Money(BigDecimal(amount).movePointRight(9).longValueExact(), "USD")

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show Vercel Gateway with its dashboard, off until turned on, sending its key only to the gateway`() {
        val provider = make()
        assertEquals("vercel-gateway", provider.id)
        assertEquals("Vercel Gateway", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://vercel.com/dashboard/ai-gateway", provider.definition.profile.links.dashboard)
        assertEquals(listOf(AddAccountWay.FORM), provider.definition.accounts?.ways)
        assertEquals(listOf("ai-gateway.vercel.sh"), provider.definition.keyDestinations)
    }

    @ParameterizedTest
    @ValueSource(strings = ["95.50", "0", "1245.67", "-1.25", "0.123456789"])
    fun `should show the credit balance as exact dollars, with no ceiling, no percentage and no window`(amount: String) {
        for (value in listOf(amount, "\"$amount\"")) {
            val usage = make(body = "{\"balance\":$value}").refreshPlain().usage()
            val quota = usage.quotas.first()
            assertEquals(QuotaType.ModelSpecific("AI Gateway Credits"), quota.quotaType)
            assertEquals(Left.Balance(usd(amount), null), quota.left)
            assertNull(quota.percentLeft)
            assertNull(quota.window)
        }
    }

    @ParameterizedTest
    @ValueSource(strings = ["not JSON", "{}", """{"balance":"abc"}""", """{"balance":"0x10"}""", """{"balance":null}""", """{"balance":true}"""])
    fun `should fail at reading the answer when Vercel reports no readable balance`(body: String) {
        val product = make(body = body)
        product.refreshPlain().failure()
        assertEquals(DataSourceError.Step.MAPPING, product.defaultAccount.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when Vercel refuses the key`(status: Int) {
        assertEquals(UsageError.AuthenticationRequired, make(status = status).refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(ints = [429, 500])
    fun `should fail at fetching when Vercel is rate-limiting or down`(status: Int) {
        val product = make(status = status)
        product.refreshPlain().failure()
        assertEquals(DataSourceError.Step.FETCH, product.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should be unavailable and ask for a key when none is saved or set`() {
        val product = make(vault = MemoryVault())
        assertFalse(product.isPlainAvailable())
        assertEquals(UsageError.AuthenticationRequired, product.refreshPlain().failure())
    }

    @Test
    fun `should use the environment key for the default login and each added login's own saved key`() {
        val vault = MemoryVault(mapOf("vercel-gateway.apiKey" to "personal"))
        val settings = InMemoryProviderSettings()
        val provider = make(
            environment = mapOf("AI_GATEWAY_API_KEY" to "environment"), vault = vault, settings = settings,
            replies = mapOf("Bearer environment" to """{"balance":40}""", "Bearer work" to """{"balance":"7.50"}"""),
        )
        val work = provider.accounts.add(filling = mapOf("apiKey" to "work")).done()
        assertTrue(work.isEnabled)
        assertEquals(usd("40").amountNanos, provider.refreshPlain().usage().quotas.first().dollarRemainingNanos)
        assertEquals(usd("7.50").amountNanos, provider.refreshNow(work).usage().quotas.first().dollarRemainingNanos)
        assertNull(settings.accounts(provider.id).first().probeConfig["apiKey"])
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(UsageError.AuthenticationRequired, provider.refreshNow(work).failure())
    }

    @Test
    fun `should use the key from the environment variable the person named`() {
        val settings = InMemoryProviderSettings()
        settings.setValue("MY_GATEWAY_KEY", "authEnvVar", "vercel-gateway")
        val provider = make(
            environment = mapOf("MY_GATEWAY_KEY" to "named"), vault = MemoryVault(), settings = settings,
            replies = mapOf("Bearer named" to """{"balance":3}"""),
        )
        assertEquals(usd("3").amountNanos, provider.refreshPlain().usage().quotas.first().dollarRemainingNanos)
    }

    @Test
    fun `should use the saved key when the environment key is blank`() {
        val provider = make(environment = mapOf("AI_GATEWAY_API_KEY" to " \n "), replies = mapOf("Bearer personal" to """{"balance":10}"""))
        assertEquals(usd("10").amountNanos, provider.refreshPlain().usage().quotas.first().dollarRemainingNanos)
    }
}
