package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.util.Base64

/**
 * A Keychain item another CLI keeps: found by its service and, when several logins share one, its
 * account; a go-keyring item's password is stored as `go-keyring-base64:<base64>` and read as
 * what it encodes.
 */
class KeychainItemTest {
    private fun read(json: String, password: String, security: FakeSecurity = FakeSecurity { SecurityResult(0, password) }): Credential? {
        val item = KeychainCredential.from(Json.parseToJsonElement(json))
        return KeychainReader(item, security, userName = "someone").find()?.credential
    }

    @Test
    fun `should read the token a go-keyring password encodes`() {
        val encoded = "go-keyring-base64:" + Base64.getEncoder().encodeToString("gho_abc123".toByteArray())
        val credential = read("""{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}""", encoded)
        assertEquals("gho_abc123", credential?.get("token"))
    }

    @Test
    fun `should read a go-keyring item stored plain as it is`() {
        val credential = read("""{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}""", "gho_plain")
        assertEquals("gho_plain", credential?.get("token"))
    }

    @Test
    fun `should read the keychain item of the named account when several logins share a service`() {
        val security = FakeSecurity { SecurityResult(0, "t") }
        read("""{"service":"gh:github.com","account":"octocat","token":"$"}""", "t", security)
        assertEquals(listOf("find-generic-password", "-s", "gh:github.com", "-a", "octocat", "-w"), security.calls.first())
    }

    @Test
    fun `should keep a keychain item's account and encoding apart from its key, and when written out and read back`() {
        val item = KeychainCredential.from(
            Json.parseToJsonElement("""{"service":"gh:github.com","account":"octocat","encoding":"goKeyringBase64","token":"$"}"""),
        )
        assertEquals(mapOf("token" to "$"), item.fields)
        assertEquals("octocat", item.account)
        assertEquals(item, KeychainCredential.from(item.toJson()))
    }
}
