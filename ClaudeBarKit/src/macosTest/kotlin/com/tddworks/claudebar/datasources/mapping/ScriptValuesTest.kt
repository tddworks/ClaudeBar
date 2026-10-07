package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageQuota
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlin.test.Test
import kotlin.test.assertEquals

/** A script reads the settings its definition hands it as `context.values`; a setting left blank never filled its template, so it isn't there. */
class ScriptValuesTest {
    private val script = """
    function read(response, context) {
        const limit = context.values.limit;
        return {quotas: [{type: 'time', name: 'Monthly', percentRemaining: limit ? Number(limit) : 7,
                          resetText: context.values.manual === undefined ? 'no manual' : 'manual ' + context.values.manual}]};
    }
    """

    private fun read(values: Map<String, String>): UsageQuota =
        ScriptMapper("s.js", script, values, JavaScriptCoreEngine(), { 0.0 }).read(Response("{}"), MappingFacts(), "acme").quotas.first()

    @Test
    fun `should hand a script the settings the person filled in`() {
        val quota = read(mapOf("limit" to "40", "manual" to "12"))
        assertEquals(40.0, quota.percentRemaining)
        assertEquals("manual 12", quota.resetText)
    }

    @Test
    fun `should leave out a setting the person left blank`() {
        val quota = read(mapOf("limit" to "{{setting.limit}}", "manual" to "{{setting.manual}}"))
        assertEquals(7.0, quota.percentRemaining)
        assertEquals("no manual", quota.resetText)
    }

    @Test
    fun `should keep a script's setting templates when its definition is saved and read back`() {
        val mapping = DefinitionJson.decodeFromJsonElement<ScriptMapping>(Json.parseToJsonElement("""{"file":"s.js","values":{"limit":"{{setting.limit}}"}}"""))
        assertEquals(mapOf("limit" to "{{setting.limit}}"), mapping.values)
        assertEquals(mapping, DefinitionJson.decodeFromJsonElement<ScriptMapping>(DefinitionJson.encodeToJsonElement(mapping)))
    }
}
