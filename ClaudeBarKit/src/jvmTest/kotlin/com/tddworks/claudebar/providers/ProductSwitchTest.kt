package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * *The product's switch* (CANONICAL §1): Claude on or off hides every login of it, and keeps
 * each login's own *Pause*. On upgrade, the old switch — which was the plain login's — keeps
 * meaning what it did.
 */
class ProductSwitchTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun work() = ProviderAccountConfig("work", "work", probeConfig = mapOf("codexHome" to "/tmp/work", "chatgptAccountId" to "work"))

    private fun codex(settings: InMemoryProviderSettings) =
        stub.make(stub.builtIns.definition("codex"), settings.accounts("codex"), settings = settings)

    private fun twoLogins() = InMemoryProviderSettings().also { it.addAccount(work(), "codex") }

    @Test
    fun `should show every login of a provider in the lineup when the provider is on`() {
        val codex = codex(twoLogins())

        val shown = codex.accounts.count(codex::isInLineup)
        assertTrue(codex.isEnabled)
        assertEquals(2, shown)
    }

    @Test
    fun `should hide every login but keep each login's own switch when the provider is turned off`() {
        val codex = codex(twoLogins())

        codex.isEnabled = false

        assertEquals(0, codex.accounts.count(codex::isInLineup))
        assertEquals(2, codex.accounts.count { it.isEnabled })
    }

    @Test
    fun `should keep the provider on and its other logins shown when one login is paused`() {
        val codex = codex(twoLogins())

        codex.defaultAccount.isEnabled = false

        assertTrue(codex.isEnabled)
        assertFalse(codex.plainIsInLineup)
        assertTrue(codex.isInLineup(codex.accounts[1]))
    }

    @Test
    fun `should remember the provider's switch and a login's pause apart across a relaunch`() {
        val settings = twoLogins()
        val first = codex(settings)
        first.defaultAccount.isEnabled = false
        first.isEnabled = false

        val again = codex(settings)

        assertFalse(again.isEnabled)
        assertFalse(again.defaultAccount.isEnabled)
        assertTrue(again.accounts[1].isEnabled)
    }

    // Upgrade: the old switch was the plain login's

    @Test
    fun `should pause only the plain login when the old switch was off and another login is on, after an upgrade`() {
        val settings = twoLogins()
        settings.setEnabled(false, "codex")

        val codex = codex(settings)

        assertTrue(codex.isEnabled)
        assertFalse(codex.defaultAccount.isEnabled)
        assertTrue(codex.isInLineup(codex.accounts[1]))
    }

    @Test
    fun `should turn the provider off when the old switch was off and no other login is on, after an upgrade`() {
        val settings = InMemoryProviderSettings()
        settings.setEnabled(false, "codex")

        val codex = codex(settings)

        assertFalse(codex.isEnabled)
        assertTrue(codex.defaultAccount.isEnabled)
    }

    @Test
    fun `should honour the old switch only once after an upgrade`() {
        val settings = twoLogins()
        settings.setEnabled(false, "codex")
        val first = codex(settings)
        first.defaultAccount.isEnabled = true

        val again = codex(settings)

        assertTrue(again.isEnabled)
        assertTrue(again.defaultAccount.isEnabled)
    }
}
