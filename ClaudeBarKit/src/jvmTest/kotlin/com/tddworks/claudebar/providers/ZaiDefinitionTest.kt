package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** Z.ai as data: the quota-limit response read by `zai-usage.js` — the old probe's fixtures, quota for quota. */
class ZaiDefinitionTest {
    private fun read(body: String, providerId: String = "zai"): UsageSnapshot {
        val definition = TestDefinitions.builtIn("zai")
        val source = testDataSources().make(definition.dataSources[0], providerId, scripts = TestDefinitions.builtIns::script)
        try {
            return source.read(Response(body = body.encodeToByteArray()))
        } catch (error: DataSourceError) {
            throw error.reason
        }
    }

    // Sample data

    private val sampleQuotaLimitResponse = """
    {
      "data": {
        "limits": [
          { "type": "TOKENS_LIMIT", "percentage": 65 },
          { "type": "TIME_LIMIT", "percentage": 30, "currentValue": 100, "usage": 3600, "usageDetails": [] }
        ]
      }
    }
    """

    private val sampleQuotaLimitResponseOnlyTokens = """{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "percentage": 45 } ] } }"""
    private val sampleQuotaLimitResponseEmpty = """{ "data": { "limits": [] } }"""
    private val sampleQuotaLimitResponseFullUsage = """{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "percentage": 100 } ] } }"""
    private val sampleQuotaLimitResponseNoUsage = """{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "percentage": 0 } ] } }"""

    // Quota limit parsing

    @Test
    fun `should show a quota for each limit Z_ai reports`() {
        assertEquals(2, read(sampleQuotaLimitResponse).quotas.size)
    }

    @Test
    fun `should show 35% of the session left when Z_ai reports 65% of tokens used`() {
        val tokenQuota = read(sampleQuotaLimitResponse).quotas.firstOrNull { it.quotaType == QuotaType.Session }
        assertNotNull(tokenQuota)
        assertEquals(35.0, tokenQuota?.percentRemaining)
    }

    @Test
    fun `should show the token limit as the session`() {
        assertNotNull(read(sampleQuotaLimitResponse).quotas.firstOrNull { it.quotaType == QuotaType.Session })
    }

    @Test
    fun `should show the time limit as the MCP quota, with 70% left when 30% is used`() {
        val timeQuota = read(sampleQuotaLimitResponse).quotas.firstOrNull { it.quotaType == QuotaType.TimeLimit("MCP") }
        assertNotNull(timeQuota)
        assertEquals(70.0, timeQuota?.percentRemaining)
    }

    @Test
    fun `should show only the session when Z_ai reports only a token limit`() {
        val snapshot = read(sampleQuotaLimitResponseOnlyTokens)
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.Session, snapshot.quotas.first().quotaType)
        assertEquals(55.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should report every quota as Z_ai's`() {
        val snapshot = read(sampleQuotaLimitResponse)
        assertEquals("zai", snapshot.providerId)
        assertTrue(snapshot.quotas.all { it.providerId == "zai" })
    }

    @Test
    fun `should show nothing left when Z_ai reports 100% used`() {
        assertEquals(0.0, read(sampleQuotaLimitResponseFullUsage).quotas.first().percentRemaining)
    }

    @Test
    fun `should show everything left when Z_ai reports 0% used`() {
        assertEquals(100.0, read(sampleQuotaLimitResponseNoUsage).quotas.first().percentRemaining)
    }

    // Error handling

    @Test
    fun `should fail to read usage when Z_ai answers with something that is not JSON`() {
        assertThrows<UsageError> { read("not json") }
    }

    @Test
    fun `should fail to read usage when Z_ai reports no limits`() {
        assertThrows<UsageError> { read(sampleQuotaLimitResponseEmpty) }
    }

    @Test
    fun `should fail to read usage when Z_ai answers with an error instead of usage`() {
        assertThrows<UsageError> { read("""{ "error": "Unauthorized" }""") }
    }

    // TOKENS_LIMIT entries told apart by their unit: 3 → 5 hours, 6 → 7 days, 7 → monthly; TIME_LIMIT 5 → MCP.

    private val sampleQuotaLimitResponseRealZai = """
    {
      "data": {
        "limits": [
          { "type": "TIME_LIMIT", "unit": 5, "percentage": 1, "nextResetTime": 1778591596997 },
          { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13, "nextResetTime": 1778100911330 },
          { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 46, "nextResetTime": 1778418796990 }
        ]
      }
    }
    """

    @Test
    fun `should show the session, the weekly quota and MCP when Z_ai reports all three`() {
        val snapshot = read(sampleQuotaLimitResponseRealZai)
        assertEquals(3, snapshot.quotas.size)
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Session })
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Weekly })
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.TimeLimit("MCP") })
    }

    @Test
    fun `should show a 5-hour token limit as the session (unit 3)`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.Session, snapshot.quotas.first().quotaType)
        assertEquals(87.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should show a 7-day token limit as the weekly quota (unit 6)`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "unit": 6, "percentage": 46 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.Weekly, snapshot.quotas.first().quotaType)
        assertEquals(54.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should show the session and the weekly quota apart when Z_ai reports two token limits`() {
        val snapshot = read(sampleQuotaLimitResponseRealZai)
        val sessionQuotas = snapshot.quotas.filter { it.quotaType == QuotaType.Session }
        val weeklyQuotas = snapshot.quotas.filter { it.quotaType == QuotaType.Weekly }
        assertEquals(1, sessionQuotas.size)
        assertEquals(1, weeklyQuotas.size)
        assertNotEquals(sessionQuotas.first().percentRemaining, weeklyQuotas.first().percentRemaining)
    }

    @Test
    fun `should show a token limit with no window as the session`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "percentage": 65 } ] } }""")
        assertEquals(QuotaType.Session, snapshot.quotas.first().quotaType)
    }

    @Test
    fun `should still show a token limit whose window is unknown, named by its unit`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "unit": 99, "percentage": 25 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        val type = snapshot.quotas.first().quotaType
        assertTrue(type is QuotaType.ModelSpecific && type.name.contains("99"), "Expected a model-specific quota for an unknown unit, got $type")
    }

    @Test
    fun `should show all left for a negative usage and none left past 100% when Z_ai reports an out-of-range percentage`() {
        val snapshot = read(
            """{ "data": { "limits": [ { "type": "TOKENS_LIMIT", "percentage": -10 }, { "type": "TIME_LIMIT", "percentage": 150 } ] } }""",
        )
        assertEquals(2, snapshot.quotas.size)
        assertEquals(100.0, snapshot.quotas[0].percentRemaining)
        assertEquals(0.0, snapshot.quotas[1].percentRemaining)
    }

    // CREDIT_LIMIT: credit-based plans (e.g. GLM Coding Lite), with the same `unit` meanings.

    private val sampleQuotaLimitResponseCreditPlan = """
    {
      "data": {
        "limits": [
          { "type": "CREDIT_LIMIT", "unit": 3, "number": 5, "usage": 2000,
            "currentValue": 0, "remaining": 2000, "percentage": 0 },
          { "type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 10000,
            "currentValue": 2004, "remaining": 7995, "percentage": 20,
            "nextResetTime": 1786112351998 }
        ],
        "level": "lite"
      }
    }
    """

    @Test
    fun `should show the session and the weekly quota when the plan counts credits`() {
        val snapshot = read(sampleQuotaLimitResponseCreditPlan)
        assertEquals(2, snapshot.quotas.size)
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Session })
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Weekly })
    }

    @Test
    fun `should show a 5-hour credit limit as the session (unit 3)`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "CREDIT_LIMIT", "unit": 3, "percentage": 13 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.Session, snapshot.quotas.first().quotaType)
        assertEquals(87.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should show a 7-day credit limit as the weekly quota (unit 6)`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.Weekly, snapshot.quotas.first().quotaType)
        assertEquals(80.0, snapshot.quotas.first().percentRemaining)
    }

    @Test
    fun `should still show a credit limit whose window is unknown, named by its unit`() {
        val snapshot = read("""{ "data": { "limits": [ { "type": "CREDIT_LIMIT", "unit": 99, "percentage": 5 } ] } }""")
        assertEquals(1, snapshot.quotas.size)
        assertEquals(QuotaType.ModelSpecific("Credits (unit 99)"), snapshot.quotas.first().quotaType)
    }

    @Test
    fun `should show the session, the weekly quota and MCP when Z_ai mixes token and credit limits`() {
        val snapshot = read(
            """{ "data": { "limits": [
              { "type": "TOKENS_LIMIT", "unit": 3, "percentage": 13 },
              { "type": "CREDIT_LIMIT", "unit": 6, "percentage": 20 },
              { "type": "TIME_LIMIT", "unit": 5, "percentage": 1 }
            ] } }""",
        )
        assertEquals(3, snapshot.quotas.size)
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Session })
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.Weekly })
        assertTrue(snapshot.quotas.any { it.quotaType == QuotaType.TimeLimit("MCP") })
    }
}
