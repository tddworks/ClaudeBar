package com.tddworks.claudebar.datasources.lookup

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * `jsonFile.record` — a login file holding several records: the one that can be refreshed and
 * lasts longest answers, and a refreshed token goes back into that record only. `defaults` fill
 * what a record lacks.
 */
class CredentialRecordTest {
    @TempDir
    lateinit var root: File

    private val url get() = File(root, "auth.json")

    private fun file(json: String): JSONFileReader {
        url.writeText(json)
        val credential = JSONFileCredential.from(Json.parseToJsonElement("""
        {"path":"${url.path}","token":"$.key","refreshToken":"$.refresh_token","expiresAt":"$.expires_at",
         "issuer":"$.issuer","record":{"prefer":"refreshToken","latest":"expiresAt"},
         "defaults":{"issuer":"https://auth.acme.test"}}
        """))
        return JSONFileReader(credential, root.path) { null }
    }

    private fun written() = Json.parseToJsonElement(url.readText()).jsonObject.mapValues { it.value.jsonObject }

    private val three = """
    {"a":{"key":"no-refresh","expires_at":"2099-01-01T00:00:00Z"},
     "b":{"key":"short","refresh_token":"r-b","expires_at":"2026-01-01T00:00:00.123456Z"},
     "c":{"key":"long","refresh_token":"r-c","expires_at":"2027-01-01T00:00:00Z","issuer":"https://login.acme.test/"}}
    """

    @Test
    fun `should use the record that can be renewed and lasts longest when a login file holds several`() {
        val found = requireNotNull(file(three).find())
        assertEquals("long", found.credential.token)
        assertEquals("https://login.acme.test/", found.credential["issuer"])
    }

    @Test
    fun `should fill what a record lacks from the definition's defaults without ever writing them back`() {
        val found = requireNotNull(file("""{"only":{"key":"k","refresh_token":"r"}}""").find())
        assertEquals("https://auth.acme.test", found.credential["issuer"])

        found.save!!(found.credential.with("token", "renewed"))

        val only = written().getValue("only")
        assertEquals(JsonPrimitive("renewed"), only["key"])
        assertNull(only["issuer"])
    }

    @Test
    fun `should save a renewed token into its own record only, leaving every other record as it was`() {
        val found = requireNotNull(file(three).find())

        found.save!!(found.credential.with("token", "renewed").with("refreshToken", "r-c2"))

        val records = written()
        assertEquals(JsonPrimitive("renewed"), records.getValue("c")["key"])
        assertEquals(JsonPrimitive("r-c2"), records.getValue("c")["refresh_token"])
        assertEquals(JsonPrimitive("short"), records.getValue("b")["key"])
        assertEquals(JsonPrimitive("no-refresh"), records.getValue("a")["key"])
    }

    @Test
    fun `should find no key when no record in the login file holds one`() {
        assertNull(file("""{"a":{"email":"x"},"b":"not a record"}""").find())
    }
}
