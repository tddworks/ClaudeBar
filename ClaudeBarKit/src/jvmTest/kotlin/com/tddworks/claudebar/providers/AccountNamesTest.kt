package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * What an account is called: the name the person gave it, else the email its login holds,
 * else the product's name — and the product's name alone while it is the only login to tell apart.
 */
class AccountNamesTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun login(id: String, email: String?, label: String = "") =
        ProviderAccountConfig(id, label, email, probeConfig = mapOf("codexHome" to "/tmp/$id", "chatgptAccountId" to id))

    private fun codex(settings: InMemoryProviderSettings, logins: List<ProviderAccountConfig> = emptyList()) =
        stub.make(stub.builtIns.definition("codex"), logins, settings = settings)

    // Display name

    @Test
    fun `should call a login by its label, else its email, else the product's name`() {
        val codex = codex(InMemoryProviderSettings(), listOf(login("a", "a@example.com", "Work"), login("b", "b@example.com")))

        assertEquals("Work", codex.accounts[1].displayName)
        assertEquals("b@example.com", codex.accounts[2].displayName)
        assertEquals("Codex", codex.defaultAccount.displayName)
    }

    @Test
    fun `should show the email when a login's label is blank`() {
        val codex = codex(InMemoryProviderSettings(), listOf(login("a", "a@example.com", "   ")))

        assertEquals("a@example.com", codex.accounts[1].displayName)
    }

    // The pill's name

    @Test
    fun `should call a single login by the product's name`() {
        val codex = codex(InMemoryProviderSettings())

        assertFalse(codex.accounts.hasSeveral)
        assertEquals("Codex", codex.lineupName(codex.defaultAccount))
    }

    @Test
    fun `should call several logins by their display names`() {
        val codex = codex(InMemoryProviderSettings(), listOf(login("a", "a@example.com", "Work")))

        assertTrue(codex.accounts.hasSeveral)
        assertEquals(listOf("Codex", "Work"), codex.accounts.all.map(codex::lineupName))
    }

    @Test
    fun `should stop telling a login apart when the other is paused`() {
        val codex = codex(InMemoryProviderSettings(), listOf(login("a", "a@example.com")))

        codex.accounts[1].isEnabled = false

        assertFalse(codex.accounts.hasSeveral)
        assertEquals("Codex", codex.lineupName(codex.defaultAccount))
    }

    // Rename

    @Test
    fun `should save a renamed login's label and keep who it is`() {
        val settings = InMemoryProviderSettings()
        val work = login("a", "a@example.com")
        settings.addAccount(work, "codex")
        val codex = codex(settings, listOf(work))

        codex.accounts.rename(codex.accounts[1], "  Acme  ")

        assertEquals("Acme", codex.accounts[1].displayName)
        assertEquals("Acme", settings.accounts("codex").first().label)
        assertEquals(work.probeConfig, settings.accounts("codex").first().probeConfig)
        assertEquals("codex.a", codex.accounts[1].id)
    }

    @Test
    fun `should keep the default login's name after a relaunch`() {
        val settings = InMemoryProviderSettings()
        val first = codex(settings)
        first.accounts.rename(first.defaultAccount, "Personal")

        val relaunched = codex(settings)

        assertEquals("Personal", relaunched.defaultAccount.displayName)
    }

    @Test
    fun `should go back to the email when a login's name is cleared`() {
        val settings = InMemoryProviderSettings()
        val work = login("a", "a@example.com", "Acme")
        settings.addAccount(work, "codex")
        val codex = codex(settings, listOf(work))

        codex.accounts.rename(codex.accounts[1], "")

        assertEquals("a@example.com", codex.accounts[1].displayName)
        assertEquals("", settings.accounts("codex").first().label)
    }

    // Remove

    @Test
    fun `should forget an added login's saved settings when it is removed`() {
        val settings = InMemoryProviderSettings()
        val work = login("a", "a@example.com")
        settings.addAccount(work, "codex")
        val codex = codex(settings, listOf(work))

        codex.accounts.remove(codex.accounts[1])

        assertEquals(1, codex.accounts.size)
        assertTrue(settings.accounts("codex").isEmpty())
    }

    @Test
    fun `should keep the default login when asked to remove it`() {
        val codex = codex(InMemoryProviderSettings())

        codex.accounts.remove(codex.defaultAccount)

        assertEquals(1, codex.accounts.size)
    }
}
