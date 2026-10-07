package com.tddworks.claudebar.datasources

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

class FetchModelTest {
    private val definitions = File("definitions").listFiles { f -> f.extension == "json" }.orEmpty()

    private fun fetches() = definitions.flatMap { file ->
        val provider = Json.parseToJsonElement(file.readText()) as JsonObject
        (provider["dataSources"] as? JsonArray).orEmpty().map { file.name to (it as JsonObject).getValue("fetch") }
    }

    @Test
    fun `should read the fetch of every bundled definition and write it back the same`() {
        val all = fetches()
        assertTrue(all.size > 30, "found ${all.size} fetches")
        for ((file, json) in all) {
            val fetch = Fetch.from(json)
            assertEquals(fetch, Fetch.from(fetch.toJson()), file)
        }
    }

    @Test
    fun `should read steps under http as the steps case`() {
        val fetch = Fetch.from(Json.parseToJsonElement(
            """{"http":{"steps":[{"name":"me","request":{"url":"https://x/me"},"keep":{"id":"$.id","n":{"pattern":"n=(\\d+)"}}}]}}""",
        ))
        val step = (fetch as Fetch.HttpSteps).steps.steps.single()
        assertEquals(HTTPStep.Keep.Paths(listOf("$.id")), step.keep["id"])
        assertEquals(HTTPStep.Keep.Pattern("n=(\\d+)"), step.keep["n"])
        assertEquals("GET", step.request.method)
    }

    @Test
    fun `should refuse a fetch with no tag or two`() {
        assertThrows<DefinitionError> { Fetch.from(Json.parseToJsonElement("""{"nope":{}}""")) }
        assertThrows<DefinitionError> { Fetch.from(Json.parseToJsonElement("""{"file":{"path":"a"},"directory":{"path":"b"}}""")) }
    }

    @Test
    fun `should refuse more than eight steps or a step tried more than three times`() {
        val step = """{"name":"s%d","request":{"url":"https://x"}}"""
        val nine = (1..9).joinToString(",") { step.format(it) }
        assertThrows<DefinitionError> { Fetch.from(Json.parseToJsonElement("""{"http":{"steps":[$nine]}}""")) }
        assertThrows<DefinitionError> {
            Fetch.from(Json.parseToJsonElement("""{"http":{"steps":[{"name":"a","request":{"url":"https://x"},"attempts":4}]}}"""))
        }
    }

    @Test
    fun `should read a ready marker as a phrase or a row`() {
        val call = (Fetch.from(Json.parseToJsonElement(
            """{"cli":{"cli":"tool","readyWhen":["Done",{"row":"Total"}],"screen":"rendered"}}""",
        )) as Fetch.Cli).call
        assertEquals(listOf(CLICall.ReadyMarker("Done"), CLICall.ReadyMarker("Total", endsRow = true)), call.readyWhen)
        assertEquals(CLICall.Screen.RENDERED, call.screen)
        assertEquals(20.0, call.timeout)
    }

    @Test
    fun `should find a script beside its folder unless its path is absolute`() {
        assertEquals("/ext/acme/probe.sh", ScriptCall(run = "./probe.sh", folder = "/ext/acme/").path)
        assertEquals("/bin/x", ScriptCall(run = "/bin/x", folder = "/ext").path)
        assertEquals(listOf("us-east-1", "eu-west-1"), CloudWatchCall("n", "d", listOf("m"), " us-east-1, ,eu-west-1,{{setting.r}}").regionList)
    }
}
