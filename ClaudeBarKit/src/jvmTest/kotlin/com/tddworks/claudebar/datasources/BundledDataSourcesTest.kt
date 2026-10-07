package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.lookup.FakeVault
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** Every data source every bundled definition lists is made live by the factory: each case of the definition meets its connection. */
class BundledDataSourcesTest {
    @Test
    fun `should make every data source of every bundled definition and say whether it is ready and has its key`() {
        val home = freshFolder("bundled-sources")
        val failures = mutableListOf<String>()
        var count = 0
        try {
            val sources = testDataSources(home = home.path)
            val files = File("../Modules/Providers/Resources/Providers").listFiles { f -> f.extension == "json" }.orEmpty()
            for (file in files.sortedBy { it.name }) {
                val provider = Json.parseToJsonElement(file.readText()) as JsonObject
                val id = ((provider["profile"] as? JsonObject)?.get("id") as? JsonPrimitive)?.content ?: file.nameWithoutExtension
                for (json in (provider["dataSources"] as? JsonArray).orEmpty()) {
                    val definition = DataSourceDefinition.from(json)
                    runCatching {
                        val source = sources.make(definition, id, secrets = FakeVault(), scripts = { "function read() { return {quotas: []}; }" })
                        source.isReady()
                        source.hasKey
                        source.handOffWithoutKey
                    }.onFailure { failures += "${file.name} ${definition.kind}: $it" }
                    count++
                }
            }
        } finally {
            home.deleteRecursively()
        }
        assertEquals(emptyList<String>(), failures)
        assertTrue(count >= 36, "made $count data sources")
    }
}
