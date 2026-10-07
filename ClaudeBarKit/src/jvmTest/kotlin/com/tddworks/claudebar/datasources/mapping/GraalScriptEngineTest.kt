package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * The JUnit engine answers as JavaScriptCore does on the Mac: the same cases as the native
 * ScriptMoneyTest, so a vendor suite run on the JVM reads its scripts the way the app will.
 */
class GraalScriptEngineTest {
    private fun read(output: String): UsageSnapshot {
        val definition = DataSourceDefinition(
            kind = "api", fetch = Fetch.Http(HTTPRequest(url = "https://example.test")), mapping = Mapping.Script(ScriptMapping("balance.js")),
        )
        return testDataSources().make(definition, "example", scripts = { "function read() { return $output; }" }).read(Response("{}"))
    }

    @Test
    fun `should show an exact balance without a made-up percentage when a script reports money`() {
        val quota = read("{quotas:[{type:'model',name:'Balance',left:{money:'1234567890.123456789',currency:'CNY'}}]}").quotas.first()
        assertEquals(Left.Balance(Money(1_234_567_890_123_456_789L, "CNY"), null), quota.left)
        assertNull(quota.percentLeft)
    }

    @Test
    fun `should show money left of its ceiling as a percentage when a script reports both`() {
        val quota = read("{quotas:[{type:'model',name:'Credits',left:{money:'12.50',of:'50',currency:'USD'}}]}").quotas.first()
        assertEquals(25.0, quota.percentLeft)
    }

    @Test
    fun `should group a quota under the name the script gives it`() {
        val usage = read("{quotas:[{type:'time',name:'Kimi 5h',percentRemaining:40,group:'Kimi'},{type:'time',name:'Solo',percentRemaining:9}]}")
        assertEquals(listOf("Kimi", null), usage.quotas.map { it.group })
    }

    @Test
    fun `should give the run no host access`() {
        val run = GraalScriptEngine().run(emptyList(), emptyMap(), emptyMap(), "typeof Java")
        assertEquals(ScriptRun.Value("undefined"), run)
    }
}
