package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/**
 * OpenAI API as data: the organization's spend over the last 30 days from the Admin API, asked
 * from a start date the engine computes, read by `openai-costs.js`.
 */
class OpenAIDefinitionTest {
    /** 2026-10-05 14:30:00 UTC; 29 days before its midnight is 2026-09-06. */
    private val now = 1_791_210_600.0
    private val costsURL = "https://api.openai.com/v1/organization/costs?start_time=1788652800&bucket_width=1d&limit=30&group_by=line_item"

    private val costs = """
    {"object":"page","data":[
     {"object":"bucket","start_time":1788652800,"end_time":1788739200,"results":[
      {"object":"organization.costs.result","amount":{"value":12.5,"currency":"usd"},"line_item":"Text tokens"},
      {"object":"organization.costs.result","amount":{"value":"2.25","currency":"usd"},"line_item":"Web search tool calls"}]},
     {"object":"bucket","start_time":1788739200,"end_time":1788825600,"results":[
      {"object":"organization.costs.result","amount":{"value":0.1,"currency":"usd"},"line_item":"Text tokens"},
      {"object":"organization.costs.result","amount":{"value":null,"currency":"usd"},"line_item":null}]}],
     "has_more":false,"next_page":null}
    """

    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** The provider, and the requests it sent. */
    private fun make(
        body: String = costs, status: Int = 200, environment: Map<String, String> = mapOf("OPENAI_ADMIN_KEY" to "sk-admin"),
        vault: MemoryVault = MemoryVault(),
    ): Pair<Provider, List<HttpCall>> {
        val stub = StubbedProvider().also { stubs += it }
        stub.answerHTTP(body, status)
        stub.environment = environment
        stub.now = { now }
        return stub.makeProvider("openai", vault = vault) to stub.http.sent
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should be OpenAI API, off until turned on, with its usage page and status`() {
        val (openai, _) = make()
        assertEquals("openai", openai.id)
        assertEquals("OpenAI API", openai.name)
        assertEquals(false, openai.plainIsInLineup)
        assertEquals("https://platform.openai.com/usage", openai.definition.profile.links.dashboard)
        assertEquals("https://status.openai.com", openai.definition.profile.links.status)
    }

    @Test
    fun `should ask for the last 30 days of spend from today's UTC midnight, with the Admin key`() {
        val (openai, seen) = make()
        openai.refreshPlain()
        assertEquals(costsURL, seen.lastOrNull()?.url)
        assertEquals("Bearer sk-admin", seen.lastOrNull()?.headers?.get("Authorization"))
    }

    @Test
    fun `should add up the spend exactly, with a line per item, largest first`() {
        val usage = make().first.refreshPlain().usage()
        val cost = usage.costUsage!!
        assertEquals(14_850_000_000, cost.totalCostNanos)
        assertEquals("Last 30 days", cost.resetText)
        assertEquals(listOf("Text tokens", "Web search tool calls"), cost.lines.map { it.label })
        assertEquals(listOf(12_600_000_000, 2_250_000_000), cost.lines.map { it.amountNanos })
        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should show nothing spent when the organization used nothing`() {
        val usage = make(body = """{"object":"page","data":[],"has_more":false,"next_page":null}""").first.refreshPlain().usage()
        assertEquals(0L, usage.costUsage?.totalCostNanos)
        assertEquals(true, usage.costUsage?.lines?.isEmpty())
    }

    @Test
    fun `should use a pasted Admin key when there is no environment key`() {
        val (openai, seen) = make(environment = emptyMap(), vault = MemoryVault(mapOf("openai.apiKey" to "sk-pasted")))
        openai.refreshPlain()
        assertEquals("Bearer sk-pasted", seen.lastOrNull()?.headers?.get("Authorization"))
    }

    @Test
    fun `should ask for a key when there is none`() {
        val (openai, _) = make(environment = emptyMap())
        assertEquals(UsageError.AuthenticationRequired, openai.refreshPlain().failure())
        assertEquals(DataSourceError.Step.LOOKUP, openai.defaultAccount.lastFailedStep)
    }

    @ParameterizedTest
    @ValueSource(ints = [401, 403])
    fun `should ask for an organization Admin key when OpenAI refuses the key`(status: Int) {
        val (openai, _) = make(status = status)
        assertEquals(UsageError.SessionExpired("Use an organization Admin API key; project keys can't read spend."), openai.refreshPlain().failure())
    }

    @ParameterizedTest
    @ValueSource(strings = ["not json", """{"object":"page"}"""])
    fun `should fail reading the spend when OpenAI's answer has no buckets`(body: String) {
        val (openai, _) = make(body = body)
        openai.refreshPlain().failure()
        assertEquals(DataSourceError.Step.MAPPING, openai.defaultAccount.lastFailedStep)
    }
}
