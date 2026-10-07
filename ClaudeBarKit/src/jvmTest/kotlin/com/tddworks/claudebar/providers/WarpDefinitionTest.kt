package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.math.abs

/** Warp as data: the monthly credits and add-on credits from Warp's GraphQL API with an API key, read by `warp-credits.js`. */
class WarpDefinitionTest {
    private val credits = """
    {"data":{"user":{"__typename":"UserOutput","user":{
     "requestLimitInfo":{"isUnlimited":false,"nextRefreshTime":"2026-02-28T19:16:33.462988Z","requestLimit":1500,"requestsUsedSinceLastRefresh":5},
     "bonusGrants":[{"requestCreditsGranted":20,"requestCreditsRemaining":10,"expiration":"2026-03-01T10:00:00Z"}],
     "workspaces":[{"bonusGrantsInfo":{"grants":[{"requestCreditsGranted":"15","requestCreditsRemaining":"5","expiration":"2026-03-15T10:00:00Z"}]}}]}}}}
    """

    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** The provider, and the requests it sent. */
    private fun make(
        body: String = credits, status: Int = 200, environment: Map<String, String> = mapOf("WARP_API_KEY" to "wk-key"),
        vault: MemoryVault = MemoryVault(),
    ): Pair<Provider, List<HttpCall>> {
        val stub = StubbedProvider().also { stubs += it }
        stub.http.answer = { call ->
            if (call.url != "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo" || call.method != "POST") {
                Response(400, body = ByteArray(0))
            } else {
                Response(status, body = body.encodeToByteArray())
            }
        }
        stub.environment = environment
        return stub.makeProvider("warp", vault = vault) to stub.http.sent
    }

    private fun seconds(text: String): Double = Instant.parse(text).toEpochMilli() / 1000.0

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should be Warp, off until turned on, with its dashboard and icon`() {
        val (warp, _) = make()
        assertEquals("warp", warp.id)
        assertEquals("Warp", warp.name)
        assertEquals(false, warp.plainIsInLineup)
        assertEquals("https://app.warp.dev/settings/billing", warp.definition.profile.links.dashboard)
        assertEquals("WarpIcon", warp.definition.profile.look.icon)
    }

    @Test
    fun `should ask Warp the way its app does, with the key, as JSON, and as Warp`() {
        val (warp, seen) = make()
        warp.refreshPlain()
        val request = seen.last()
        assertEquals("Bearer wk-key", request.headers["Authorization"])
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("Warp/1.0", request.headers["User-Agent"])
        assertEquals("warp-app", request.headers["x-warp-client-id"])
        val body = Json.parseToJsonElement(request.body!!.decodeToString()) as JsonObject
        assertEquals("GetRequestLimitInfo", (body["operationName"] as? JsonPrimitive)?.content)
        assertEquals(true, (body["query"] as? JsonPrimitive)?.content?.contains("requestLimitInfo"))
    }

    @Test
    fun `should show the monthly credits used and when they refresh`() {
        val usage = make().first.refreshPlain().usage()
        val monthly = usage.quotas.first { it.quotaType == QuotaType.TimeLimit("Monthly") }
        assertTrue(abs(monthly.percentRemaining - (1495.0 / 1500.0 * 100)) < 0.0001)
        assertEquals("5/1500 credits", monthly.resetText)
        assertTrue(abs((monthly.resetsAtSeconds ?: 0.0) - seconds("2026-02-28T19:16:33.462988Z")) < 0.001)
    }

    @Test
    fun `should add up the add-on credits of the person and every workspace, with the soonest expiry`() {
        val usage = make().first.refreshPlain().usage()
        val addOn = usage.quotas.first { it.quotaType == QuotaType.ModelSpecific("Add-on") }
        assertTrue(abs(addOn.percentRemaining - (15.0 / 35.0 * 100)) < 0.0001)
        assertEquals("15/35 credits left", addOn.resetText)
        assertEquals(seconds("2026-03-01T10:00:00Z"), addOn.resetsAtSeconds)
    }

    @Test
    fun `should show an unlimited plan as full, with no refresh countdown`() {
        val body = """{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":true,"nextRefreshTime":"2026-02-28T19:16:33Z","requestLimit":0,"requestsUsedSinceLastRefresh":40},"bonusGrants":[],"workspaces":[]}}}}"""
        val usage = make(body = body).first.refreshPlain().usage()
        assertEquals(1, usage.quotas.size)
        val monthly = usage.quotas.first()
        assertEquals(100.0, monthly.percentRemaining)
        assertEquals("Unlimited", monthly.resetText)
        assertNull(monthly.resetsAtSeconds)
    }

    @Test
    fun `should read numbers Warp sends as text`() {
        val body = """{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":"false","nextRefreshTime":"2026-02-28T19:16:33Z","requestLimit":"100","requestsUsedSinceLastRefresh":"25"}}}}}"""
        assertEquals(75.0, make(body = body).first.refreshPlain().usage().quotas.first().percentRemaining)
    }

    @Test
    fun `should use a pasted key when there is no environment key`() {
        val (warp, seen) = make(environment = emptyMap(), vault = MemoryVault(mapOf("warp.apiKey" to "wk-pasted")))
        warp.refreshPlain()
        assertEquals("Bearer wk-pasted", seen.lastOrNull()?.headers?.get("Authorization"))
    }

    @Test
    fun `should ask for a key when there is none`() {
        val (warp, _) = make(environment = emptyMap())
        assertEquals(UsageError.AuthenticationRequired, warp.refreshPlain().failure())
        assertEquals(DataSourceError.Step.LOOKUP, warp.defaultAccount.lastFailedStep)
    }

    @Test
    fun `should ask for a new key when Warp answers that the key is unauthorized`() {
        val (warp, _) = make(body = """{"errors":[{"message":"Unauthorized"}]}""")
        assertEquals(UsageError.SessionExpired("Create a new API key in Warp: Settings → Platform → API Keys."), warp.refreshPlain().failure())
    }

    @Test
    fun `should say what Warp answered when it reports another error`() {
        val (warp, _) = make(body = """{"errors":[{"message":"Something broke"}]}""")
        assertEquals(UsageError.ExecutionFailed("Warp: Something broke"), warp.refreshPlain().failure())
    }

    @Test
    fun `should fail reading the credits when Warp's answer has no limit`() {
        val (warp, _) = make(body = """{"data":{"user":{"__typename":"UserOutput","user":{}}}}""")
        warp.refreshPlain().failure()
        assertEquals(DataSourceError.Step.MAPPING, warp.defaultAccount.lastFailedStep)
    }
}
