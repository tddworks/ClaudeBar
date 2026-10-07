package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.DefinitionError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

class MappingModelTest {
    private val definitions = File("definitions").listFiles { f -> f.extension == "json" }.orEmpty()

    private fun mappings() = definitions.flatMap { file ->
        val provider = Json.parseToJsonElement(file.readText()) as JsonObject
        (provider["dataSources"] as? JsonArray).orEmpty().mapNotNull { source ->
            (source as JsonObject)["mapping"]?.let { file.name to it }
        }
    }

    private fun mapping(json: String) = Mapping.from(Json.parseToJsonElement(json))

    @Test
    fun `should read the mapping of every bundled definition and write it back the same`() {
        val all = mappings()
        assertTrue(all.size > 30, "found ${all.size} mappings")
        for ((file, json) in all) {
            val mapping = Mapping.from(json)
            assertEquals(mapping, Mapping.from(mapping.toJson()), file)
        }
    }

    @Test
    fun `should read one value or a list of them wherever a rule takes several`() {
        val rule = (mapping(
            """{"json":{"email":"${'$'}credential.email","cost":{"remaining":"a","limit":1000},
               "quotas":[{"kind":"session","usedPercent":["${'$'}header.x","used"],"resetsAt":{"epochSeconds":"at"},"window":{"hours":5}}]}}""",
        ) as Mapping.Json).mapping

        assertEquals(listOf("\$credential.email"), rule.email)
        assertEquals(listOf(CostRule(remaining = listOf(ValueRef.Path("a")), limit = Amount.Value(listOf(ValueRef.Constant(1000.0))))), rule.cost)
        assertEquals(listOf(ValueRef.Path("\$header.x"), ValueRef.Path("used")), rule.quotas.single().usedPercent)
        assertEquals(listOf(ResetRef.EpochSeconds("at")), rule.quotas.single().resetsAt)
        assertEquals(listOf(DurationRef.Fixed(18000.0)), rule.quotas.single().window)
    }

    @Test
    fun `should read a name or a plan written as plain text`() {
        val rule = (mapping("""{"json":{"plan":"$.plan_type","quotas":[{"kind":"time","name":"Monthly"}]}}""") as Mapping.Json).mapping

        assertEquals(PlanRule("$.plan_type"), rule.plan)
        assertEquals(NameRule(text = "Monthly"), rule.quotas.single().name)
    }

    @Test
    fun `should read an amount in minor units with its decimal places`() {
        val rule = (mapping("""{"json":{"cost":{"used":{"amount":"used","decimals":["places",2]}}}}""") as Mapping.Json).mapping

        assertEquals(Amount.MinorUnits("used", listOf(ValueRef.Path("places"), ValueRef.Constant(2.0))), rule.cost.single().used)
    }

    @Test
    fun `should read an error by its name or with its text`() {
        val text = (mapping(
            """{"text":{"errors":[{"contains":["a"],"error":"authenticationRequired"},{"contains":["b"],"error":{"parseFailed":"Not yet"}},
               {"contains":["c"],"error":"sessionExpired"}],"quotas":[]}}""",
        ) as Mapping.Text).mapping

        assertEquals(
            listOf(ErrorRef.AuthenticationRequired, ErrorRef.ParseFailed("Not yet"), ErrorRef.SessionExpired(null)),
            text.errors.map { it.error },
        )
    }

    @Test
    fun `should read a script mapping and the usage mapping`() {
        assertEquals(Mapping.Script(ScriptMapping("s.js", listOf("plan"))), mapping("""{"script":{"file":"s.js","credential":["plan"]}}"""))
        assertEquals(Mapping.Usage, mapping("""{"usage":{}}"""))
        assertEquals(JsonObject(mapOf("usage" to JsonObject(emptyMap()))), Mapping.Usage.toJson())
    }

    @Test
    fun `should refuse a mapping with no tag, two, or a kind it doesn't know`() {
        assertThrows<DefinitionError> { mapping("""{"nope":{}}""") }
        assertThrows<DefinitionError> { mapping("""{"json":{},"text":{"quotas":[]}}""") }
        assertThrows<DefinitionError> { mapping("""{"json":{"quotas":[{"kind":"hourly"}]}}""") }
        assertThrows<DefinitionError> { mapping("""{"text":{"errors":[{"contains":["x"],"error":"teapot"}],"quotas":[]}}""") }
    }

    @Test
    fun `should write an expired session with no hint as its plain name`() {
        assertEquals(JsonPrimitive("sessionExpired"), ErrorRef.SessionExpired(null).toJson())
        assertEquals(ErrorRef.SessionExpired("Sign in again"), ErrorRef.from(ErrorRef.SessionExpired("Sign in again").toJson()))
    }
}
