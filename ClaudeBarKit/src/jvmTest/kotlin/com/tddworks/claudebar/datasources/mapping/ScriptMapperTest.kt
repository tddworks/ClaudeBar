package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** The script mapper around its engine: what a script is handed, and how what it returns is read. */
class ScriptMapperTest {
    /** An engine that answers [answer] and keeps what it was asked. */
    private class FakeEngine(private val answer: ScriptRun) : ScriptEngine {
        var input: JsonObject? = null
        var humanDate: ((String) -> Double?)? = null

        override fun run(sources: List<String>, strings: Map<String, String>, functions: Map<String, (String) -> Double?>, expression: String): ScriptRun {
            input = Json.parseToJsonElement(strings.getValue("__input")).jsonObject
            humanDate = functions["humanDate"]
            return answer
        }
    }

    private fun mapper(engine: ScriptEngine, source: String? = "function read() {}", values: Map<String, String> = emptyMap()) =
        ScriptMapper("s.js", source, values, engine, { 1_700_000_000.0 })

    private fun returning(json: String) = FakeEngine(ScriptRun.Value(json))

    @Test
    fun `should hand a script the response, the clock, and only the settings that were filled in`() {
        val engine = returning("""{"quotas":[]}""")

        mapper(engine, values = mapOf("limit" to "40", "blank" to "{{setting.blank}}"))
            .read(Response(status = 200, body = """{"a":1}""".encodeToByteArray()), MappingFacts(credential = mapOf("plan" to "pro")), "acme")

        val input = engine.input!!
        assertEquals("1", input["response"]!!.jsonObject["json"]!!.jsonObject["a"]!!.jsonPrimitive.content)
        assertEquals(1_700_000_000.0, input["context"]!!.jsonObject["now"]!!.jsonPrimitive.content.toDouble())
        assertEquals(mapOf("limit" to "40"), input["context"]!!.jsonObject["values"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content })
        assertEquals("pro", input["context"]!!.jsonObject["credential"]!!.jsonObject["plan"]!!.jsonPrimitive.content)
    }

    @Test
    fun `should let a script read a reset time a person would write`() {
        val engine = returning("""{"quotas":[]}""")
        mapper(engine).read(Response("{}"), MappingFacts(), "acme")

        assertEquals(1_700_000_000.0 + 7200, engine.humanDate!!("in 2h"))
    }

    @Test
    fun `should say the script is missing when its file is not there`() {
        val error = assertThrows<UsageError.ParseFailed> { mapper(returning("{}"), source = null).read(Response("{}"), MappingFacts(), "acme") }
        assertEquals("Mapping script 's.js' is missing", error.reason)
    }

    @Test
    fun `should fail to read when the script fails to load, throws, or returns nothing`() {
        val load = assertThrows<UsageError.ParseFailed> { mapper(FakeEngine(ScriptRun.LoadFailed("SyntaxError"))).read(Response("{}"), MappingFacts(), "acme") }
        val threw = assertThrows<UsageError.ParseFailed> { mapper(FakeEngine(ScriptRun.Threw("TypeError: x"))).read(Response("{}"), MappingFacts(), "acme") }
        val nothing = assertThrows<UsageError.ParseFailed> { mapper(FakeEngine(ScriptRun.Value(null))).read(Response("{}"), MappingFacts(), "acme") }

        assertEquals("Mapping script 's.js' failed to load: SyntaxError", load.reason)
        assertEquals("TypeError: x", threw.reason)
        assertEquals("Mapping script 's.js' returned nothing", nothing.reason)
    }

    @Test
    fun `should report the failure a script names`() {
        assertThrows<UsageError.AuthenticationRequired> {
            mapper(returning("""{"error":"authenticationRequired"}""")).read(Response("{}"), MappingFacts(), "acme")
        }
    }

    @Test
    fun `should read a script's money exactly and its account`() {
        val usage = mapper(returning(
            """{"quotas":[{"type":"time","name":"Credits","left":{"money":"12.50","of":50}}],
                "plan":"PRO","account":{"email":"me@example.com"},"cost":{"used":"0.1","kind":"extraUsage"}}""",
        )).read(Response("{}"), MappingFacts(), "acme")

        assertEquals(Left.Balance(Money(12_500_000_000, "USD"), Money(50_000_000_000, "USD")), usage.quotas.single().left)
        assertEquals("me@example.com", usage.accountEmail)
        assertEquals("PRO", usage.accountTier?.badgeText)
        assertEquals(100_000_000L, usage.costUsage?.totalCostNanos)
        assertNull(usage.costUsage?.budgetNanos)
    }

    @Test
    fun `should refuse what a script returns in a shape it doesn't know`() {
        for (output in listOf("""{"quotas":[{"type":"hourly","percentRemaining":1}]}""", """{"quotas":[{"type":"session","percentRemaining":"1"}]}""", "null")) {
            assertThrows<UsageError.ParseFailed>(output) { mapper(returning(output)).read(Response("{}"), MappingFacts(), "acme") }
        }
    }
}
