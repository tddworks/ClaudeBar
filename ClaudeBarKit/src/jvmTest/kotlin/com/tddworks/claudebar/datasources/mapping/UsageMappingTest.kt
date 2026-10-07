package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.time.Instant

/**
 * `usage` — ClaudeBar's own documented output, which an extension's script prints: `quotas[]`
 * (`type`, `percentRemaining`, `resetsAt`, `resetText`, `dollarRemaining`) and `costUsage`.
 * Read exactly as extensions are today; the script's run is the fetch's, so the output is the response.
 */
class UsageMappingTest {
    private val dollar = 1_000_000_000L

    /** The usage a script printing [output] maps to. */
    private fun usage(output: String): UsageSnapshot =
        Mapping.Usage.reader({ null }, NoScriptEngine, { 1_700_000_000.0 }).read(Response(output), MappingFacts(), "ext-acme")

    @Test
    fun `should show each quota an extension prints as the kind its type names`() {
        val usage = usage(
            """
            {"quotas":[{"type":"session","percentRemaining":85,"resetsAt":"2026-03-17T23:00:00Z"},
                       {"type":"weekly","percentRemaining":62},
                       {"type":"model:opus","percentRemaining":40},
                       {"type":"Requests","percentRemaining":12,"resetText":"Resets monthly"}]}
            """,
        )

        assertEquals(85.0, usage.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(Instant.parse("2026-03-17T23:00:00Z").epochSecond.toDouble(), usage.quota(QuotaType.Session)?.resetsAtSeconds)
        assertEquals(62.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(40.0, usage.quota(QuotaType.ModelSpecific("opus"))?.percentRemaining)
        assertEquals("Resets monthly", usage.quota(QuotaType.TimeLimit("Requests"))?.resetText)
    }

    @Test
    fun `should give a quota its conventional window, as extensions always had`() {
        val usage = usage("""{"quotas":[{"type":"session","percentRemaining":85}]}""")

        assertEquals(QuotaType.Session.conventionalWindow.seconds, usage.quota(QuotaType.Session)?.windowSeconds)
    }

    @Test
    fun `should show an extension's cost as money spent against its budget`() {
        val usage = usage("""{"costUsage":{"totalCost":10.26,"budget":50,"apiDuration":120}}""")

        assertEquals(10_260_000_000L, usage.costUsage?.totalCostNanos)
        assertEquals(50 * dollar, usage.costUsage?.budgetNanos)
        assertEquals(120.0, usage.costUsage?.apiDuration)
    }

    @Test
    fun `should fail at the mapping step when an extension prints neither quotas nor a cost`() {
        assertThrows<UsageError.ParseFailed> { usage("""{"metrics":[]}""") }
    }
}

/** A script engine that never runs — for mappings that need none. */
internal object NoScriptEngine : ScriptEngine {
    override fun run(
        sources: List<String>,
        strings: Map<String, String>,
        functions: Map<String, (String) -> Double?>,
        expression: String,
    ) = ScriptRun.Unavailable
}
