package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.DefinitionError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/** Every bundled definition's key lookup reads, and writes back as it came; a broken one says where. */
class CredentialDefinitionsTest {
    private val definitions = File("definitions").listFiles { f -> f.extension == "json" }.orEmpty()

    private fun credentials() = definitions.flatMap { file ->
        val provider = Json.parseToJsonElement(file.readText()) as JsonObject
        (provider["dataSources"] as? JsonArray).orEmpty().mapNotNull { source -> (source as JsonObject)["credential"]?.let { file.name to it } }
    }

    @Test
    fun `should read the key lookup of every bundled definition and write it back the same`() {
        val all = credentials()
        assertTrue(all.size > 20, "found ${all.size} credentials")
        for ((file, json) in all) {
            val lookup = CredentialLookup.from(json)
            assertEquals(lookup, CredentialLookup.from(lookup.toJson()), file)
            assertTrue(lookup.lookupOrder.isNotEmpty(), file)
        }
    }

    @Test
    fun `should refuse a key lookup with no tag or two, saying where`() {
        assertThrows<DefinitionError> { lookup("""{"nope":"x"}""") }
        assertThrows<DefinitionError> { lookup("""{"setting":"a","environment":"B"}""") }
        val error = assertThrows<DefinitionError> { lookup("""{"sqlite":{"path":"~/x.db"}}""") }
        assertTrue("credential.sqlite" in error.message!!, error.message)
    }

    @Test
    fun `should read an OAuth refresh with the defaults a definition leaves out`() {
        val refresh = (lookup("""{"setting":"k","refresh":{"oauth2":{"tokenURL":"https://x/token","clientId":"c","dueWhen":{}}}}""")
            as CredentialLookup.Refreshing).refresh as CredentialRefresh.OAuth2
        assertEquals(OAuth2Refresh.BodyFormat.FORM, refresh.refresh.bodyFormat)
        assertEquals(OAuth2Refresh.Expiry(), refresh.refresh.dueWhen)
        assertNull(refresh.refresh.every)
    }

    @Test
    fun `should read an instant with any fraction of a second, and write one without`() {
        assertEquals(1_700_000_000.0, ISO8601Instant.parse("2023-11-14T22:13:20Z"))
        assertEquals(1_700_000_000.138, ISO8601Instant.parse("2023-11-14T22:13:20.138930Z")!!, 1e-6)
        assertEquals(1_700_000_000.0, ISO8601Instant.parse("2023-11-15T00:13:20+02:00"))
        assertNull(ISO8601Instant.parse("yesterday"))
        assertEquals("2023-11-14T22:13:20Z", ISO8601Instant.format(1_700_000_000.9))
    }

    @Test
    fun `should read text an app stored as bytes as UTF-8, or UTF-16 when every other byte is zero`() {
        assertEquals("{\"plan\":1}", StoredText.decode("{\"plan\":1}".encodeToByteArray()))
        assertEquals("secret-token", StoredText.decode("secret-token".toByteArray(Charsets.UTF_16LE)))
    }
}
