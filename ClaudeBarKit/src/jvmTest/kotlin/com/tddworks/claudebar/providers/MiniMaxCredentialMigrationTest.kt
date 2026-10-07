package com.tddworks.claudebar.providers

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The key the old MiniMax card saved moves into the vault for the default login only; an added login never inherits it. */
class MiniMaxCredentialMigrationTest {
    @Test
    fun `should move the old MiniMax key into secure storage for the default login only`() {
        val defaults = MemoryLegacyStore("com.claudebar.credentials.minimax-api-key" to "old")
        val credentials = MemoryCredentials()
        val vault = ProviderVault(credentials, defaults)

        assertNull(vault.secret("apiKey", "minimax.work"))
        assertEquals("old", vault.secret("apiKey", "minimax"))
        assertEquals("old", credentials.get("provider.minimax.apiKey"))
        assertFalse(defaults.contains("com.claudebar.credentials.minimax-api-key"))
        assertTrue(vault.delete("apiKey", "minimax"))
        assertNull(vault.secret("apiKey", "minimax"))
    }
}
