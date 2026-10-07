package com.tddworks.claudebar.providers

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Vercel's key moves into the vault for the default login only — from the Keychain item the old card used, or from UserDefaults before that. */
class VercelCredentialMigrationTest {
    @Test
    fun `should move the old Vercel Keychain key to the default login, never to an added one`() {
        val credentials = MemoryCredentials()
        credentials.save("old-secure", "vercel-ai-gateway-api-key")
        val vault = ProviderVault(credentials, MemoryLegacyStore())

        assertNull(vault.secret("apiKey", "vercel-gateway.work"))
        assertEquals("old-secure", vault.secret("apiKey", "vercel-gateway"))
        assertEquals("old-secure", credentials.get("provider.vercel-gateway.apiKey"))
        assertNull(credentials.get("vercel-ai-gateway-api-key"))
        assertTrue(vault.delete("apiKey", "vercel-gateway"))
        assertNull(vault.secret("apiKey", "vercel-gateway"))
    }

    @Test
    fun `should move a Vercel key saved before the Keychain into the default login too`() {
        val defaults = MemoryLegacyStore("com.claudebar.credentials.vercel-api-key" to "older")
        val vault = ProviderVault(MemoryCredentials(), defaults)

        assertEquals("older", vault.secret("apiKey", "vercel-gateway"))
        assertFalse(defaults.contains("com.claudebar.credentials.vercel-api-key"))
    }
}
