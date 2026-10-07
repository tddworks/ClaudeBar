package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * `$context.<file>.<field>` in a JSON mapping — a value from a context file the data source reads
 * beside its answer, such as the email a tool keeps in its own account file.
 */
class ContextPathTest {
    private fun mapping(json: String): JSONMapping = (Mapping.from(Json.parseToJsonElement(json)) as Mapping.Json).mapping

    private fun read(mapping: JSONMapping, context: Map<String, Map<String, String>>): UsageSnapshot =
        JSONMapper(mapping) { 0.0 }.read(Response("""{"used":25}"""), MappingFacts(context = context), "acme")

    @Test
    fun `should show the email a context file holds`() {
        val mapping = mapping("""{"json":{"email":["${'$'}context.account.email"],"quotas":[]}}""")

        val usage = read(mapping, mapOf("account" to mapOf("email" to "person@example.com")))

        assertEquals("person@example.com", usage.accountEmail)
    }

    @Test
    fun `should show no email when the context file has none, and the next path still answers`() {
        val mapping = mapping("""{"json":{"email":["${'$'}context.account.email","${'$'}credential.email"],"quotas":[]}}""")

        val none = read(mapping, emptyMap())
        val fallback = JSONMapper(mapping) { 0.0 }.read(
            Response("{}"),
            MappingFacts(credential = mapOf("email" to "key@example.com"), context = mapOf("account" to emptyMap())),
            "acme",
        )

        assertNull(none.accountEmail)
        assertEquals("key@example.com", fallback.accountEmail)
    }

    @Test
    fun `should read a context value anywhere a mapping reads a path`() {
        val mapping = mapping("""{"json":{"quotas":[{"kind":"session","name":"Session","usedPercent":"${'$'}context.limits.used"}]}}""")

        val usage = read(mapping, mapOf("limits" to mapOf("used" to "40")))

        assertEquals(60.0, usage.quota(QuotaType.Session)?.percentRemaining)
    }
}
