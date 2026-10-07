package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.systemDataSources
import com.tddworks.claudebar.quotas.CostLine
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScriptMoneyTest {
    private val dollar = 1_000_000_000L

    /** The script's answer read by a data source the factory made on this Mac, as the Swift suite did. */
    private fun read(output: String): UsageSnapshot {
        val definition = DataSourceDefinition(
            kind = "api", fetch = Fetch.Http(HTTPRequest(url = "https://example.test")), mapping = Mapping.Script(ScriptMapping("balance.js")),
        )
        val source = systemDataSources().make(definition, "example", scripts = { "function read() { return $output; }" })
        return source.read(Response("{}"))
    }

    @Test
    fun `should show an exact balance without a made-up percentage when a script reports money`() {
        val quota = read("{quotas:[{type:'model',name:'Balance',left:{money:'1234567890.123456789',currency:'CNY'}}]}").quotas.first()
        assertEquals(Left.Balance(Money(1_234_567_890_123_456_789L, "CNY"), null), quota.left)
        assertNull(quota.percentLeft)
        assertNull(quota.window)
    }

    @Test
    fun `should show money left of its ceiling as a percentage when a script reports both`() {
        val usage = read("{quotas:[{type:'model',name:'Credits',left:{money:'12.50',of:'50',currency:'USD'}}]}")
        assertEquals(Left.Balance(Money(12_500_000_000, "USD"), Money(50 * dollar, "USD")), usage.quotas.first().left)
        assertEquals(25.0, usage.quotas.first().percentLeft)
    }

    @Test
    fun `should show a cost with each line exact against the user's budget`() {
        val usage = read("{quotas:[],cost:{used:'4.10',limit:'10',lines:[{label:'Claude Sonnet 4',used:'3.70',detail:'1.2M tokens'},{label:'Nova Pro',used:'0.40'}]}}")
        val cost = usage.costUsage!!
        assertEquals(4_100_000_000L, cost.totalCostNanos)
        assertEquals(10 * dollar, cost.budgetNanos)
        assertEquals(listOf(CostLine("Claude Sonnet 4", 3_700_000_000, "1.2M tokens"), CostLine("Nova Pro", 400_000_000, null)), cost.lines)
        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should group a quota under the name the script gives it`() {
        val usage = read("{quotas:[{type:'time',name:'Kimi 5h',percentRemaining:40,group:'Kimi'},{type:'time',name:'Solo',percentRemaining:9}]}")
        assertEquals(listOf("Kimi", null), usage.quotas.map { it.group })
    }

    @Test
    fun `should show a group with nothing to measure with its note`() {
        val usage = read("{quotas:[{type:'time',name:'Kimi 5h',percentRemaining:40,group:'Kimi'}],notes:[{group:'Copilot · me',text:'No usage reported'}]}")
        assertEquals(listOf("Kimi", "Copilot · me"), usage.quotaGroups.map { it.title })
        assertEquals("No usage reported", usage.quotaGroups.last().note)
    }

    @Test
    fun `should keep showing the percentage a script reports`() {
        assertEquals(Left.Share(37.0), read("{quotas:[{type:'session',percentRemaining:37}]}").quotas.first().left)
    }

    @Test
    fun `should refuse a missing ambiguous or invalid amount`() {
        for (quota in listOf(
            "{type:'model',name:'Balance'}",
            "{type:'model',name:'Balance',percentRemaining:50,left:{money:'1'}}",
            "{type:'model',name:'Balance',left:{money:'nope'}}",
        )) {
            assertFailsWith<DataSourceError>(quota) { read("{quotas:[$quota]}") }
        }
    }
}
