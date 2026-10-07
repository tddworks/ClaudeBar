package com.tddworks.claudebar.datasources.logs

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** The definitions ClaudeBar ships: every `usageHistory` block and price file they name reads in Kotlin as it did in Swift. */
class BundledUsageHistoryTest {
    private val folder = File("definitions")
    private val scripts = { name: String -> File(folder, name).takeIf { it.exists() }?.readText() }

    /** Each definition's own block, and its added logins' patch, by provider id. */
    private val blocks: Map<String, Pair<JsonElement, JsonElement?>> = folder.listFiles().orEmpty()
        .filter { it.extension == "json" && !it.name.endsWith("-prices.json") }
        .mapNotNull { file ->
            val root = Json.parseToJsonElement(file.readText()) as JsonObject
            val own = root["usageHistory"] ?: return@mapNotNull null
            val patch = ((root["accounts"] as? JsonObject)?.get("patch") as? JsonObject)?.get("usageHistory")
            file.nameWithoutExtension to (own to patch)
        }.toMap()

    @Test
    fun `should find the logs of every provider that keeps a usage history`() {
        assertEquals(setOf("claude", "codex", "mistral", "omp"), blocks.keys)
    }

    @Test
    fun `should read every shipped usage history and keep it when written out and read back`() {
        for ((id, block) in blocks) {
            val definition = UsageLog.Definition.from(block.first)
            assertEquals(definition, UsageLog.Definition.from(definition.toJson()), id)
            assertEquals(SwiftJson.encode(block.first.withoutDefaults()), SwiftJson.encode(definition.toJson().withoutDefaults()), id)
        }
    }

    @Test
    fun `should adapt every shipped usage history to an added login`() {
        for ((id, block) in blocks) {
            val patch = block.second ?: continue
            val definition = UsageLog.Definition.from(block.first)
            val login = definition.patched(patch).filled(mapOf("configDirectory" to "/work/a", "codexHome" to "/work/b"), "account")
            assertTrue(login.records.files.startsWith("/work/"), id)
            assertEquals(definition.records.shapes, login.records.shapes, id)
            assertEquals(emptyList<String>(), login.unfilled("account"), id)
        }
        val claude = UsageLog.Definition.from(blocks.getValue("claude").first)
        assertEquals(null, claude.patched(blocks.getValue("claude").second!!).otherApps)
        assertEquals(listOf("Claude Desktop"), claude.otherApps?.map { it.label })
    }

    @Test
    fun `should load every price file a shipped usage history names`() {
        val named = blocks.values.mapNotNull { UsageLog.Definition.from(it.first).prices?.file }
        assertTrue(named.isNotEmpty())
        for (file in named + folder.listFiles().orEmpty().map { it.name }.filter { it.endsWith("-prices.json") }) {
            val prices = PriceList.load(file, scripts)
            assertNotNull(prices, file)
            assertTrue(prices!!.models.isNotEmpty(), file)
        }
    }

    @Test
    fun `should keep the fingerprint the Swift app kept, so no kept day is summed again`() {
        // From the Swift UsageLog with home /Users/test and no environment.
        val swift = mapOf(
            "claude" to "0c3153d1ff801e4db6597ca3e32e52726402823ee0e4e2b86b7697ce2633e800",
            "codex" to "9ee4d33a70c62a2ff80fc27fb7b65ddb59bd9205c1edd8fea586c4630e11d005",
            "mistral" to "bd8b0edc707bf230a2bec8c80d98557c5664f3fd51aded9167326cbff416e6d4",
            "omp" to "7568808a47d38a4537b3eb1e990b005f5050ea7f4e7fe407c0a65ea5b52e63ec",
        )
        for ((id, block) in blocks) {
            val log = UsageLog.make(UsageLog.Definition.from(block.first), home = "/Users/test", environment = { null },
                scripts = scripts, now = { 0.0 })
            assertEquals(swift[id], log.fingerprint, id)
        }
    }

    /** The JSON with the fields a definition may leave out at their defaults removed. */
    private fun JsonElement.withoutDefaults(): JsonElement = when (this) {
        is JsonObject -> JsonObject(
            filterNot { (key, value) ->
                (key == "format" && value.toString() == "\"jsonLines\"") || (key == "id" && value == JsonArray(emptyList())) ||
                    (key == "tokens" && value == JsonObject(emptyMap()))
            }.mapValues { it.value.withoutDefaults() },
        )
        is JsonArray -> JsonArray(map { it.withoutDefaults() })
        else -> this
    }
}
