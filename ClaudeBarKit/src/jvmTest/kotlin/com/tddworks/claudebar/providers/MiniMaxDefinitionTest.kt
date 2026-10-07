package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
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
import java.net.URI

/** MiniMax as data: the old probe's fixtures through `minimax.json`, quota for quota, with its region, key and environment variable as settings. */
class MiniMaxDefinitionTest {
    private val sampleSuccessResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        { "model_name": "minimax-m2", "current_interval_total_count": 1500, "current_interval_usage_count": 255, "remains_time": 1234, "end_time": 1735689600000 }
      ]
    }
    """

    /** Token Plan responses carry percentages; the count fields are 0 there. */
    private val sampleTokenPlanResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "general", "current_interval_total_count": 0, "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100, "current_weekly_remaining_percent": 98,
          "start_time": 1787673600000, "end_time": 1787691600000, "weekly_start_time": 1787500800000, "weekly_end_time": 1788105600000
        },
        {
          "model_name": "video", "current_interval_total_count": 0, "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100, "current_weekly_remaining_percent": 100,
          "start_time": 1787673600000, "end_time": 1787760000000, "weekly_start_time": 1787500800000, "weekly_end_time": 1788105600000
        }
      ]
    }
    """

    private val sampleMultiModelResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        { "model_name": "minimax-m2", "current_interval_total_count": 1500, "current_interval_usage_count": 255, "remains_time": 1234, "end_time": 1735689600000 },
        { "model_name": "minimax-m1", "current_interval_total_count": 500, "current_interval_usage_count": 400, "remains_time": 1234, "end_time": 1735689600000 }
      ]
    }
    """

    private val sampleErrorResponse = """{ "base_resp": { "status_code": 1001, "status_msg": "invalid api key" }, "model_remains": [] }"""
    private val sampleEmptyRemainsResponse = """{ "base_resp": { "status_code": 0, "status_msg": "success" }, "model_remains": [] }"""
    private val sampleNoEndTimeResponse = """
    { "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [ { "model_name": "minimax-m2", "current_interval_total_count": 1000, "current_interval_usage_count": 500 } ] }
    """

    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** MiniMax on stubbed connections, answering only on the region's host and path, with the old probe's 30-second timeout. */
    private fun make(
        body: String = sampleSuccessResponse, status: Int = 200, region: String? = "china",
        authEnvVar: String? = null, vault: MemoryVault = MemoryVault(mapOf("minimax.apiKey" to "personal")),
        environment: Map<String, String> = emptyMap(),
    ): Provider {
        val stub = StubbedProvider().also { stubs += it }
        stub.http.answer = { call ->
            val url = URI(call.url)
            val international = call.headers["Authorization"] == "Bearer work" || region == "international"
            if (url.host != (if (international) "api.minimax.io" else "api.minimaxi.com") ||
                url.path != "/v1/token_plan/remains" || call.timeoutSeconds != 30.0
            ) {
                Response(400, body = ByteArray(0))
            } else {
                Response(status, body = body.encodeToByteArray())
            }
        }
        stub.environment = environment
        // Saved where the old card saved them: `minimax.region`, `minimax.authEnvVar`.
        stub.settings.setValue(region, "region", "minimax")
        stub.settings.setValue(authEnvVar, "authEnvVar", "minimax")
        return stub.makeProvider("minimax", vault = vault)
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should show MiniMax off until turned on, sending its key only to MiniMax's hosts and adding logins by form`() {
        val provider = make()
        assertEquals("MiniMax", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals(listOf("api.minimax.io", "api.minimaxi.com"), provider.definition.keyDestinations)
        assertEquals(listOf(AddAccountWay.FORM), provider.definition.accounts?.ways)
    }

    @Test
    fun `should show 17% left and 1245-1500 requests used when MiniMax counts the requests remaining`() {
        val quota = make().refreshPlain().usage().quotas.first()
        assertEquals(17.0, quota.percentRemaining)
        assertEquals(QuotaType.ModelSpecific("minimax-m2"), quota.quotaType)
        assertEquals("1245/1500 requests", quota.resetText)
        assertEquals(1735689600.0, quota.resetsAtSeconds)
        assertNull(quota.window?.lengthSeconds)
    }

    @Test
    fun `should show a 5-hour and a weekly window for each model when MiniMax answers with Token Plan percentages`() {
        val quotas = make(body = sampleTokenPlanResponse).refreshPlain().usage().quotas
        assertEquals(4, quotas.size)
        assertEquals(listOf(100.0, 98.0, 100.0, 100.0), quotas.map { it.percentRemaining })
        assertEquals(QuotaType.TimeLimit("general Weekly"), quotas[1].quotaType)
        assertEquals(18000.0, quotas[0].window?.lengthSeconds)
        assertEquals(604800.0, quotas[1].window?.lengthSeconds)
        assertEquals("2% used", quotas[1].resetText)
    }

    @Test
    fun `should show each model's quota, and no reset when MiniMax gives no end time`() {
        assertEquals(listOf(17.0, 80.0), make(body = sampleMultiModelResponse).refreshPlain().usage().quotas.map { it.percentRemaining })
        val quota = make(body = sampleNoEndTimeResponse).refreshPlain().usage().quotas.first()
        assertEquals(50.0, quota.percentRemaining)
        assertNull(quota.resetsAtSeconds)
    }

    @Test
    fun `should fail with MiniMax's own message, or with no data, when MiniMax reports an error or no models`() {
        assertEquals(UsageError.ExecutionFailed("MiniMax API error: invalid api key"), make(body = sampleErrorResponse).refreshPlain().failure())
        assertEquals(UsageError.NoData, make(body = sampleEmptyRemainsResponse).refreshPlain().failure())
        assertEquals(UsageError.NoData, make(body = """{"base_resp":{"status_code":0}}""").refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["not JSON", """{"base_resp":{"status_code":0},"model_remains":[{}]}"""])
    fun `should fail at reading the answer when MiniMax answers with something unreadable`(body: String) {
        val provider = make(body = body)
        provider.refreshPlain().failure()
        assertEquals(DataSourceError.Step.MAPPING, provider.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should show no data when MiniMax reports neither a count nor a percentage left`() {
        val body = """{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_total_count":0,"current_interval_usage_count":0}]}"""
        assertEquals(UsageError.NoData, make(body = body).refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["china", "international"])
    fun `should ask the saved region's MiniMax and open its dashboard`(region: String) {
        val provider = make(region = region)
        assertEquals(1, provider.refreshPlain().usage().quotas.size)
        assertEquals(if (region == "international") "platform.minimax.io" else "platform.minimaxi.com", provider.plainDashboardURL?.let { URI(it).host })
    }

    @Test
    fun `should ask MiniMax China when no region is saved`() {
        assertEquals(1, make(region = null).refreshPlain().usage().quotas.size)
    }

    @Test
    fun `should use the key from the environment variable the person named`() {
        val provider = make(authEnvVar = "MY_MINIMAX_KEY", vault = MemoryVault(), environment = mapOf("MY_MINIMAX_KEY" to "personal"))
        assertEquals(1, provider.refreshPlain().usage().quotas.size)
    }

    @Test
    fun `should show in Settings where the key is looked for, naming the person's own variable`() {
        assertEquals(
            listOf("\$MINIMAX_API_KEY", "API key saved in ClaudeBar"),
            make().configuration.definitionAsRun.dataSource("api")?.credential?.lookupOrder,
        )
        assertEquals("\$MY_MINIMAX_KEY", make(authEnvVar = "MY_MINIMAX_KEY").configuration.definitionAsRun.dataSource("api")?.credential?.lookupOrder?.first())
    }

    @Test
    fun `should use MINIMAX_API_KEY when the named environment variable is empty`() {
        val provider = make(authEnvVar = "", vault = MemoryVault(), environment = mapOf("MINIMAX_API_KEY" to "personal"))
        assertEquals(1, provider.refreshPlain().usage().quotas.size)
    }

    @Test
    fun `should use an added login's own key and region, never the environment, and ask to sign in when its key is gone`() {
        val vault = MemoryVault(mapOf("minimax.apiKey" to "personal"))
        val provider = make(vault = vault, environment = mapOf("MINIMAX_API_KEY" to "environment"))
        val work = provider.accounts.add(filling = mapOf("apiKey" to "work", "region" to "international")).done()
        assertTrue(work.isEnabled)
        assertEquals(17.0, provider.refreshNow(work).usage().quotas.first().percentRemaining)
        assertEquals("platform.minimax.io", provider.dashboardURL(work)?.let { URI(it).host })
        vault.secrets.remove("${work.id}.apiKey")
        assertEquals(UsageError.AuthenticationRequired, provider.refreshNow(work).failure())
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask to sign in again when MiniMax refuses the key`(code: Int) {
        assertEquals(UsageError.AuthenticationRequired, make(status = code).refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(ints = [429, 500])
    fun `should fail at fetching when MiniMax is rate-limiting or down`(code: Int) {
        val product = make(status = code)
        product.refreshPlain().failure()
        assertEquals(DataSourceError.Step.FETCH, product.defaultAccount.lastFailedStep)
    }
}
