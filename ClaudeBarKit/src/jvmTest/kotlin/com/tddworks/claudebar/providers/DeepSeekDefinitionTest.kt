package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.TEMP_HOME
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

class DeepSeekDefinitionTest {
    private val balance = """{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"40.00","granted_balance":"10.00","topped_up_balance":"30.00"}]}"""

    private fun HttpCall.header(name: String): String? = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    private fun make(
        body: String? = null, status: Int = 200, vault: MemoryVault = MemoryVault(mapOf("deepseek.apiKey" to "personal")),
        environment: Map<String, String> = emptyMap(), settings: InMemoryProviderSettings = InMemoryProviderSettings(),
        balancesByKey: Map<String, String>? = null,
    ): Provider {
        val definition = TestDefinitions.builtIn("deepseek")
        val answer = body ?: balance
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response {
                if (call.url != "https://api.deepseek.com/user/balance" || call.method != "GET" || call.timeoutSeconds != 30.0 ||
                    call.header("Accept") != "application/json"
                ) {
                    return Response(400, body = ByteArray(0))
                }
                if (balancesByKey != null) {
                    val reply = balancesByKey[call.header("Authorization") ?: ""] ?: return Response(401, body = ByteArray(0))
                    return Response(200, body = reply.encodeToByteArray())
                }
                return Response(status, body = answer.encodeToByteArray())
            }
        }
        val connections = testDataSources(network = network, environment = environment)
        return Provider(
            definition = definition, settings = settings, saved = settings.accounts(definition.id),
            makeDataSource = { source, account -> connections.make(source, definition.id, vault.scoped(account), TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), vault = vault, paths = HomePaths(TEMP_HOME), isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    private fun money(units: Long, currency: String) = Money(units * 1_000_000_000, currency)

    @Test
    fun `should be DeepSeek, out of the lineup until turned on, with its usage dashboard, icon and an add-login form`() {
        val provider = make()
        assertEquals("deepseek", provider.id)
        assertEquals("DeepSeek", provider.name)
        assertEquals(false, provider.plainIsInLineup)
        assertEquals("https://platform.deepseek.com/usage", provider.definition.profile.links.dashboard)
        assertEquals("DeepSeekIcon", provider.definition.profile.look.icon)
        assertEquals(listOf(AddAccountWay.FORM), provider.definition.accounts?.ways)
    }

    @Test
    fun `should show the first balance exactly in its own currency, with the paid and granted parts, and no percentage`() {
        val body = """{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.123456789","granted_balance":"10","topped_up_balance":"100"},{"currency":"USD","total_balance":"40"}]}"""
        val usage = make(body = body).refreshPlain().usage()
        val quota = usage.quotas.first()
        assertEquals(1, usage.quotas.size)
        assertEquals(QuotaType.ModelSpecific("Balance"), quota.quotaType)
        assertEquals(Left.Balance(Money(110_123_456_789, "CNY"), null), quota.left)
        assertEquals("Paid: ¥100.00 · Granted: ¥10.00", quota.resetText)
        assertNull(quota.percentLeft)
        assertNull(quota.window)
    }

    @Test
    fun `should leave out a paid or granted part that is missing or unreadable`() {
        val body = """{"balance_infos":[{"currency":"USD","total_balance":"40","granted_balance":"bad","topped_up_balance":"30"}]}"""
        assertEquals("Paid: $30.00", make(body = body).refreshPlain().usage().quotas.firstOrNull()?.resetText)
    }

    @Test
    fun `should read the default login with the environment key and each added login with its own key`() {
        val vault = MemoryVault(mapOf("deepseek.apiKey" to "personal"))
        val replies = mapOf(
            "Bearer environment" to """{"balance_infos":[{"currency":"USD","total_balance":"40"}]}""",
            "Bearer work" to """{"balance_infos":[{"currency":"CNY","total_balance":"7"}]}""",
        )
        val provider = make(vault = vault, environment = mapOf("DEEPSEEK_API_KEY" to "environment"), balancesByKey = replies)
        val work = provider.accounts.add(mapOf("apiKey" to "work")).done()
        assertTrue(work.isEnabled)
        val personalUsage = provider.refreshPlain().usage()
        val workUsage = provider.refreshNow(work).usage()
        assertEquals(Left.Balance(money(40, "USD"), null), personalUsage.quotas.firstOrNull()?.left)
        assertEquals(Left.Balance(money(7, "CNY"), null), workUsage.quotas.firstOrNull()?.left)
        assertEquals(work.id, workUsage.providerId)
    }

    @Test
    fun `should read the key from the environment variable the person named`() {
        val settings = InMemoryProviderSettings()
        settings.setValue("MY_DEEPSEEK", "authEnvVar", "deepseek")
        val provider = make(
            environment = mapOf("MY_DEEPSEEK" to "named", "DEEPSEEK_API_KEY" to "default"), settings = settings,
            balancesByKey = mapOf("Bearer named" to balance),
        )
        assertEquals(40_000_000_000, provider.refreshPlain().usage().quotas.firstOrNull()?.dollarRemainingNanos)
    }

    @Test
    fun `should read DEEPSEEK_API_KEY when the person named no variable`() {
        val settings = InMemoryProviderSettings()
        settings.setValue("", "authEnvVar", "deepseek")
        val provider = make(environment = mapOf("DEEPSEEK_API_KEY" to "default"), settings = settings, balancesByKey = mapOf("Bearer default" to balance))
        assertEquals(40_000_000_000, provider.refreshPlain().usage().quotas.firstOrNull()?.dollarRemainingNanos)
    }

    @Test
    fun `should use the saved key when the environment key is empty`() {
        val provider = make(environment = mapOf("DEEPSEEK_API_KEY" to ""), balancesByKey = mapOf("Bearer personal" to balance))
        assertEquals(40_000_000_000, provider.refreshPlain().usage().quotas.firstOrNull()?.dollarRemainingNanos)
    }

    @Test
    fun `should be unavailable and ask for a key when the default login has none`() {
        val product = make(vault = MemoryVault())
        val account = product.defaultAccount
        assertFalse(runBlocking { product.isAvailable(account) })
        assertEquals(UsageError.AuthenticationRequired, product.refreshNow(account).failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["0", "-1.25"])
    fun `should show a zero or negative balance as depleted, with no made-up percentage`(amount: String) {
        val body = """{"balance_infos":[{"currency":"USD","total_balance":"$amount"}]}"""
        val usage = make(body = body).refreshPlain().usage()
        assertEquals(QuotaStatus.DEPLETED, usage.quotas.firstOrNull()?.status)
        assertNull(usage.quotas.firstOrNull()?.percentLeft)
    }

    @ParameterizedTest
    @ValueSource(ints = [429, 500])
    fun `should fail at fetching when DeepSeek is rate limited or errors`(status: Int) {
        val product = make(status = status)
        val account = product.defaultAccount
        product.refreshNow(account).failure()
        assertEquals(DataSourceError.Step.FETCH, account.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask for a key when DeepSeek refuses it`(status: Int) {
        val product = make(status = status)
        assertEquals(UsageError.AuthenticationRequired, product.refreshNow(product.defaultAccount).failure())
    }

    @Test
    fun `should report no data when DeepSeek lists no balance`() {
        val product = make(body = """{"balance_infos":[]}""")
        assertEquals(UsageError.NoData, product.refreshNow(product.defaultAccount).failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["not JSON", """{"balance_infos":[{"currency":"USD","total_balance":"bad"}]}"""])
    fun `should fail reading the balance when it is unreadable`(body: String) {
        val product = make(body = body)
        val account = product.defaultAccount
        product.refreshNow(account).failure()
        assertEquals(DataSourceError.Step.MAPPING, account.lastFailedStep)
    }

    @Test
    fun `should say the balance is unavailable for API calls rather than show it healthy`() {
        val product = make(body = """{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"5"}]}""")
        assertEquals(
            UsageError.ExecutionFailed("DeepSeek reports that this balance is unavailable for API calls."),
            product.refreshNow(product.defaultAccount).failure(),
        )
    }

    @Test
    fun `should keep an added login's key out of settings and never fall back to the default key`() {
        val vault = MemoryVault(mapOf("deepseek.apiKey" to "personal"))
        val settings = InMemoryProviderSettings()
        val provider = make(vault = vault, environment = mapOf("DEEPSEEK_API_KEY" to "environment-default"), settings = settings)
        val work = provider.accounts.add(mapOf("apiKey" to "work")).done()
        assertNull(settings.accounts("deepseek").firstOrNull()?.probeConfig?.get("apiKey"))
        assertEquals("work", vault.secrets["${work.id}.apiKey"])
        val reloaded = make(vault = vault, settings = settings)
        assertTrue(reloaded.accounts[1].isEnabled)
        val usage = reloaded.refreshNow(reloaded.accounts[1]).usage()
        assertEquals(work.id, usage.providerId)
        reloaded.accounts[1].isEnabled = false
        assertEquals(false, make(vault = vault, settings = settings).accounts[1].isEnabled)
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(UsageError.AuthenticationRequired, provider.refreshNow(work).failure())
        assertEquals(DataSourceError.Step.LOOKUP, work.lastFailedStep)
    }
}
