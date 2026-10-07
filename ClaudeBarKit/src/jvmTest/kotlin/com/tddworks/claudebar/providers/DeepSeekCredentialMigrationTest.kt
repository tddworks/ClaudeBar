package com.tddworks.claudebar.providers

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DeepSeekCredentialMigrationTest {
    @Test
    fun `should keep the old DeepSeek key for the default login only, moved once, while an added login keeps its own key`() {
        val legacy = MemoryLegacyStore("com.claudebar.credentials.deepseek-api-key" to "old-key")
        val credentials = MemoryCredentials()
        val vault = ProviderVault(credentials, legacy)

        assertEquals("old-key", vault.secret("apiKey", "deepseek"))
        assertEquals("old-key", credentials.get("provider.deepseek.apiKey"))
        assertFalse(legacy.contains("com.claudebar.credentials.deepseek-api-key"))
        assertNull(vault.secret("apiKey", "deepseek.work"))
        vault.save("work-key", "apiKey", "deepseek.work")
        assertEquals("work-key", vault.secret("apiKey", "deepseek.work"))
        assertEquals("old-key", vault.secret("apiKey", "deepseek"))
        assertTrue(vault.delete("apiKey", "deepseek.work"))
        assertEquals("old-key", vault.secret("apiKey", "deepseek"))
    }

    @Test
    fun `should keep the old DeepSeek key and refuse to delete it when the Keychain refuses to store it`() {
        val legacy = MemoryLegacyStore("com.claudebar.credentials.deepseek-api-key" to "old-key")
        val vault = ProviderVault(RefusingCredentials(), legacy)

        assertEquals("old-key", vault.secret("apiKey", "deepseek"))
        assertNull(vault.secret("apiKey", "deepseek.work"))
        assertFalse(vault.delete("apiKey", "deepseek"))
        assertEquals("old-key", legacy.string("com.claudebar.credentials.deepseek-api-key"))
    }
}
