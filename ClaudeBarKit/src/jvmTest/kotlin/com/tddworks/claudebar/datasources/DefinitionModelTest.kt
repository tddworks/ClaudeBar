package com.tddworks.claudebar.datasources

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/** Every data source a bundled definition lists, decoded whole and written back the same. */
class DefinitionModelTest {
    @Test
    fun `should read every data source of every bundled definition and write it back the same`() {
        val files = File("definitions").listFiles { f -> f.extension == "json" }.orEmpty()
        var count = 0
        for (file in files) {
            val provider = Json.parseToJsonElement(file.readText()) as JsonObject
            for (json in (provider["dataSources"] as? JsonArray).orEmpty()) {
                val definition = DataSourceDefinition.from(json)
                assertEquals(definition, DataSourceDefinition.from(definition.toJson()), "${file.name} ${definition.kind}")
                count++
            }
        }
        assertTrue(count >= 36, "read $count data sources")
    }

    @Test
    fun `should refuse an errors key that names no fact`() {
        val json = """{"kind":"api","fetch":{"http":{"url":"https://x"}},"mapping":{"usage":{}},"errors":{"http.429":"noData"}}"""
        assertThrows<DefinitionError> { DataSourceDefinition.from(Json.parseToJsonElement(json)) }
    }
}

/**
 * A field that identifies a login — the credential's account id, or the email a context file
 * holds — written as the mapping writes paths, and decoded once into what it points at.
 */
class IdentityFieldTest {
    private fun identity(field: String) = Identity.from(Json.parseToJsonElement("""{"field":"$field","equals":"x"}"""))

    @Test
    fun `should identify a login by the key's value when the definition gives a bare name`() {
        assertEquals(IdentityField.CredentialValue("account"), identity("account").field)
    }

    @Test
    fun `should identify a login by the key's value when the definition points into the key`() {
        assertEquals(IdentityField.CredentialValue("account"), identity("\$credential.account").field)
    }

    @Test
    fun `should identify a login by a field of a context file when the definition points there`() {
        assertEquals(IdentityField.ContextValue("account", "email"), identity("\$context.account.email").field)
    }

    @Test
    fun `should reject a definition that points to a context file but no field in it`() {
        assertThrows<DefinitionError> { identity("\$context.account") }
    }

    @Test
    fun `should write a login's identifying field back as it was written`() {
        for (field in listOf("account", "\$context.account.email")) {
            val encoded = identity(field).toJson()
            assertEquals(identity(field), Identity.from(encoded))
            assertTrue(encoded.toString().contains(field))
        }
    }
}

/**
 * A definition as data a login can adapt: an RFC 7396 merge patch changes what differs, and a
 * login's values fill `{{account.x}}` — one definition, never a copy per login.
 */
class DefinitionPatchTest {
    private val rpc = """
    {
      "kind": "rpc",
      "label": "RPC",
      "fetch": { "jsonRpc": { "cli": "codex", "args": ["app-server"], "call": "account/rateLimits/read" } },
      "mapping": { "json": { "quotas": [{ "kind": "session", "at": "${'$'}.result.primary", "usedPercent": "usedPercent" }] } },
      "requiresFiles": ["~/.codex/auth.json"],
      "verifyBeforeBackground": true,
      "fallback": "tty"
    }
    """

    private fun definition(json: String = rpc) = DataSourceDefinition.from(Json.parseToJsonElement(json))
    private fun patch(json: String) = Json.parseToJsonElement(json)

    @Test
    fun `should keep a definition when it is written out and read back`() {
        assertEquals(definition(), DataSourceDefinition.from(definition().toJson()))
    }

    @Test
    fun `should change only what a login's patch names and keep the rest of the definition`() {
        val patched = definition().patched(patch("""{ "requiresFiles": ["{{account.codexHome}}/auth.json"] }"""))
        assertEquals(listOf("{{account.codexHome}}/auth.json"), patched.requiresFiles)
        assertEquals("rpc", patched.kind)
        assertEquals("tty", patched.fallback?.to)
        assertEquals(definition().mapping, patched.mapping)
    }

    @Test
    fun `should drop what a login's patch sets to null`() {
        val patched = definition().patched(patch("""{ "fallback": null, "verifyBeforeBackground": null }"""))
        assertNull(patched.fallback)
        assertFalse(patched.verifyBeforeBackground)
    }

    @Test
    fun `should merge a login's patch into nested parts of the definition and replace its lists whole`() {
        val patched = definition().patched(patch("""
        { "fetch": { "jsonRpc": { "args": ["-c", "x", "app-server"],
                                  "environment": { "set": { "CODEX_HOME": "/tmp/a" } } } } }
        """))
        val call = (patched.fetch as Fetch.JsonRpc).call
        assertEquals(listOf("-c", "x", "app-server"), call.args)
        assertEquals("codex", call.cli)
        assertEquals("account/rateLimits/read", call.call)
        assertEquals(mapOf("CODEX_HOME" to "/tmp/a"), call.environment.set)
    }

    @Test
    fun `should fill every account placeholder with the login's own values`() {
        val template = definition().patched(patch("""
        { "requiresFiles": ["{{account.codexHome}}/auth.json"],
          "identity": { "field": "account", "equals": "{{account.chatgptAccountId}}" } }
        """))
        val filled = template.filled(mapOf("codexHome" to "/Users/me/codex-work", "chatgptAccountId" to "acct-1"), "account")
        assertEquals(listOf("/Users/me/codex-work/auth.json"), filled.requiresFiles)
        assertEquals("acct-1", filled.identity?.equals)
        assertTrue(filled.unfilled("account").isEmpty())
    }

    @Test
    fun `should leave placeholders other than the login's for the fetch to fill`() {
        val template = definition("""
        { "kind": "api",
          "fetch": { "http": { "url": "https://example.com", "headers": { "Authorization": "Bearer {{token}}" } } },
          "mapping": { "json": { "quotas": [] } } }
        """)
        val request = (template.filled(mapOf("codexHome" to "/tmp"), "account").fetch as Fetch.Http).request
        assertEquals("Bearer {{token}}", request.headers["Authorization"])
    }

    @Test
    fun `should name a value the login doesn't have as unfilled`() {
        val template = definition().patched(patch("""{ "requiresFiles": ["{{account.codexHome}}/auth.json"] }"""))
        assertEquals(listOf("codexHome"), template.filled(emptyMap(), "account").unfilled("account"))
    }
}
