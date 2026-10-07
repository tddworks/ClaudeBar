package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceDefinition
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/**
 * An added login runs a built-in data source re-read through JSON — patched and filled.
 * Anything lost on the way would silently change what it fetches.
 */
class DefinitionRoundTripTest {
    @ParameterizedTest
    @ValueSource(strings = ["claude", "codex", "deepseek", "minimax", "vercel-gateway", "commandcode", "ampcode", "kiro", "cursor", "grok", "opencode-go", "zai", "kimi", "copilot", "alibaba", "gemini", "antigravity", "bedrock", "omp", "mistral"])
    fun `should fetch the same way when a built-in data source is written out and read back`(id: String) {
        val definition = TestDefinitions.builtIn(id)

        for (source in definition.dataSources) {
            val again = DataSourceDefinition.from(Json.parseToJsonElement(source.toJson().toString()))
            assertEquals(source, again, "$id.${source.kind} changed on the round trip")
        }
    }

    @Test
    fun `should leave a data source unchanged when an added login patches nothing and fills no values`() {
        val codex = TestDefinitions.builtIn("codex")

        for (source in codex.dataSources) {
            assertEquals(source, source.patched(JsonObject(emptyMap())).filled(emptyMap(), "account"))
        }
    }
}
