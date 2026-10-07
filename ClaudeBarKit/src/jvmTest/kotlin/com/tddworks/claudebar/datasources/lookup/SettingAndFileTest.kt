package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Template
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * A key the person pasted into ClaudeBar (`setting`, kept in its vault, never in a file) —
 * *Start from: API*. The `file` fetch half of the Swift suite belongs to the fetch area.
 */
class SettingAndFileTest {
    private val api = lookup("""{ "setting": "apiKey" }""")

    private fun reader(vault: FakeVault) = CredentialFinders(
        providerId = "openrouter", home = "/nowhere", environment = { null }, security = FakeSecurity { SecurityResult(1, "") },
        secrets = vault, database = FakeDatabase { _, _ -> emptyList() }, browserCookies = FakeCookies(), browserStorage = FakeStorage(),
    ).reader(api)

    @Test
    fun `should send the key the person saved in ClaudeBar as the definition says`() {
        val credential = reader(FakeVault(mapOf("openrouter.apiKey" to "sk-or-1"))).find()?.credential

        assertEquals("Bearer sk-or-1", Template.fill("Bearer {{token}}", credential))
    }

    @Test
    fun `should ask for a key at the lookup step when none is saved`() {
        assertNull(reader(FakeVault()).find())
    }

    @Test
    fun `should name where the key is kept, never its value, when it is saved in ClaudeBar`() {
        assertEquals(listOf("API key saved in ClaudeBar"), api.lookupOrder)
    }
}
