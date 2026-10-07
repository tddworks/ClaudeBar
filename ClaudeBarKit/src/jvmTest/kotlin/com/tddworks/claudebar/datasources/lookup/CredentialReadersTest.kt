package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.Paths
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class CredentialReadersTest {
    private val home = "/Users/someone"

    // KeychainReader.decode

    @Test
    fun `should read a keychain login the Mac hands back hex-encoded`() {
        val json = """{"claudeAiOauth":{"accessToken":"hex-token"}}"""
        val hex = json.encodeToByteArray().joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

        assertEquals(json, KeychainReader.decode(hex)?.decodeToString())
    }

    @Test
    fun `should read a keychain login stored as plain JSON as it is`() {
        val json = """{"claudeAiOauth":{"accessToken":"plain-token"}}"""

        assertEquals(json, KeychainReader.decode(json)?.decodeToString())
    }

    // KeychainReader write-back

    @Test
    fun `should save a renewed keychain login over the same item as one printable line, keeping its other fields`() {
        val password = """
        {
          "claudeAiOauth": {
            "accessToken": "old-token",
            "expiresAt": 1748276587173,
            "scopes": ["user:inference", "user:profile"]
          }
        }
        """.trimIndent()
        val security = FakeSecurity { if (it.first() == "find-generic-password") SecurityResult(0, password) else SecurityResult(0, "") }
        val reader = KeychainReader(
            KeychainCredential(
                service = "Some-credentials",
                fields = mapOf("token" to "$.claudeAiOauth.accessToken", "expiresAt" to "$.claudeAiOauth.expiresAt"),
            ),
            security,
            userName = "someone",
        )
        val found = requireNotNull(reader.find())
        val refreshed = found.credential.with("token", "refreshed-token").with("expiresAt", "1800000000000")

        found.save!!(refreshed)

        val write = security.calls.last()
        assertEquals(listOf("add-generic-password", "-U", "-s", "Some-credentials", "-a", "someone", "-w"), write.dropLast(1))
        val payload = write.last()
        // `security find-generic-password -w` hex-encodes any password holding a byte outside
        // printable ASCII, so the payload must stay printable.
        assertTrue(payload.all { it.code in 0x20..0x7e })
        assertFalse("\n" in payload)
        val oauth = Json.parseToJsonElement(payload).jsonObject.getValue("claudeAiOauth").jsonObject
        assertEquals("refreshed-token", oauth.getValue("accessToken").jsonPrimitive.content)
        assertEquals(1_800_000_000_000, oauth.getValue("expiresAt").jsonPrimitive.long)
        assertEquals(JsonArray(listOf(JsonPrimitive("user:inference"), JsonPrimitive("user:profile"))), oauth["scopes"])
    }

    @Test
    fun `should find no key when the keychain item isn't there`() {
        val reader = KeychainReader(
            KeychainCredential(service = "Missing", fields = mapOf("token" to "$.token")),
            FakeSecurity { SecurityResult(44, "") },
        )

        assertNull(reader.find())
    }

    // EnvironmentReader

    @Test
    fun `should use an environment key without surrounding whitespace, never save it, and find none when it is empty`() {
        val trimmed = EnvironmentReader("KEY", { "  sk-1\n" })
        val empty = EnvironmentReader("KEY", { "" })

        assertEquals("sk-1", trimmed.find()?.credential?.token)
        assertNull(trimmed.find()?.save)
        assertNull(empty.find())
    }

    // Paths.expand

    @Test
    fun `should place a path starting with a tilde under the home folder and leave an absolute path alone`() {
        assertEquals("/Users/someone/.claude/.credentials.json", Paths.expand("~/.claude/.credentials.json", home) { null })
        assertEquals("/Users/someone", Paths.expand("~", home) { null })
        assertEquals("/etc/absolute.json", Paths.expand("/etc/absolute.json", home) { null })
    }

    @Test
    fun `should place a path under the folder a variable names when the variable is set`() {
        val path = Paths.expand("\${CONFIG_DIR:-~}/.claude.json", home) { if (it == "CONFIG_DIR") "/custom" else null }

        assertEquals("/custom/.claude.json", path)
    }

    @Test
    fun `should place a path under its default folder when the variable is unset or empty`() {
        assertEquals("/Users/someone/.claude.json", Paths.expand("\${CONFIG_DIR:-~}/.claude.json", home) { null })
        assertEquals("/Users/someone/.claude.json", Paths.expand("\${CONFIG_DIR:-~}/.claude.json", home) { "" })
    }

    // CredentialDocument.updated

    private val fields = mapOf(
        "token" to "$.oauth.accessToken",
        "refreshToken" to "$.oauth.refreshToken",
        "expiresAt" to "$.oauth.expiresAt",
    )

    private fun json(text: String) = Json.parseToJsonElement(text).jsonObject

    @Test
    fun `should keep each saved value's type when a renewed login is written back`() {
        val document = json("""{"oauth":{"accessToken":"old","expiresAt":1000,"refreshToken":"r"}}""")

        val updated = CredentialDocument.updated(
            document,
            Credential(mapOf("token" to "new", "expiresAt" to "2000", "refreshToken" to "1234")),
            fields,
        )

        val oauth = updated.getValue("oauth").jsonObject
        assertEquals(JsonPrimitive("new"), oauth["accessToken"])
        assertEquals(JsonPrimitive(2000L), oauth["expiresAt"])
        // A string that looks like a number stays a string.
        assertEquals(JsonPrimitive("1234"), oauth["refreshToken"])
    }

    @Test
    fun `should write a new expiry time as a number when the login file had none`() {
        val updated = CredentialDocument.updated(
            json("""{"oauth":{"accessToken":"old"}}"""),
            Credential(mapOf("token" to "new", "expiresAt" to "2000")),
            fields,
        )

        assertEquals(JsonPrimitive(2000L), updated.getValue("oauth").jsonObject["expiresAt"])
    }

    @Test
    fun `should keep every field the definition doesn't name and add none when a renewed login is written back`() {
        val document = json("""{"oauth":{"accessToken":"old","scopes":["a","b"]},"other":"kept"}""")

        val updated = CredentialDocument.updated(
            document,
            Credential(mapOf("token" to "new", "refreshedAt" to "2026-01-01T00:00:00Z")),
            fields,
        )

        val oauth = updated.getValue("oauth").jsonObject
        assertEquals(JsonArray(listOf(JsonPrimitive("a"), JsonPrimitive("b"))), oauth["scopes"])
        assertEquals(JsonPrimitive("kept"), updated["other"])
        // A credential value with no field in the file is not written.
        assertNull(oauth["refreshedAt"])
        assertNull(updated["refreshedAt"])
    }

    // JSONFileReader write-back

    @Test
    fun `should keep a login file's other fields and number types when a renewed login is saved into it`(@TempDir directory: File) {
        File(directory, "auth.json").writeText("""{"oauth":{"accessToken":"old","expiresAt":1000,"scopes":["x"]}}""")
        val reader = JSONFileReader(JSONFileCredential(PathPattern("~/auth.json"), fields), directory.path) { null }
        val found = requireNotNull(reader.find())

        found.save!!(found.credential.with("token", "new").with("expiresAt", "2000"))

        val oauth = (Json.parseToJsonElement(File(directory, "auth.json").readText()) as JsonObject).getValue("oauth").jsonObject
        assertEquals(JsonPrimitive("new"), oauth["accessToken"])
        assertEquals(JsonPrimitive(2000L), oauth["expiresAt"])
        assertEquals(JsonArray(listOf(JsonPrimitive("x"))), oauth["scopes"])
    }
}
