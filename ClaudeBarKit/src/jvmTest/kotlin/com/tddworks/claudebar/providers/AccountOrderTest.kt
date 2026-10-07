package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The order of a provider's logins is the person's: *Personal* above *Work* is a preference,
 * not a fact about the CLI — so the default login moves like the others and is found by being
 * the default, not by being first.
 */
class AccountOrderTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun login(id: String) = ProviderAccountConfig(
        id, id.replaceFirstChar(Char::uppercase), "$id@example.com",
        probeConfig = mapOf("codexHome" to "/tmp/$id", "chatgptAccountId" to id),
    )

    private fun codex(settings: InMemoryProviderSettings) =
        stub.make(stub.builtIns.definition("codex"), settings.accounts("codex"), settings = settings)

    private fun saved(vararg ids: String) = InMemoryProviderSettings().also { settings ->
        for (id in ids) settings.addAccount(login(id), "codex")
    }

    @Test
    fun `should list logins in the order they were added, the default first`() {
        val codex = codex(saved("work", "side"))

        assertEquals(listOf("default", "work", "side"), codex.accounts.all.map { it.accountId })
    }

    @Test
    fun `should keep a moved login's place after a relaunch`() {
        val settings = saved("work", "side")
        val first = codex(settings)

        first.accounts.move(first.accounts[2], 0)

        assertEquals(listOf("side", "default", "work"), first.accounts.all.map { it.accountId })
        assertEquals(listOf("side", "default", "work"), codex(settings).accounts.all.map { it.accountId })
    }

    @Test
    fun `should still find the default login wherever it sits`() {
        val codex = codex(saved("work"))

        codex.accounts.move(codex.defaultAccount, 1)

        assertTrue(codex.defaultAccount.isDefault)
        assertEquals("codex", codex.defaultAccount.id)
        assertEquals(listOf("work", "default"), codex.accounts.all.map { it.accountId })
    }

    @Test
    fun `should put a login added later at the end of the saved order`() {
        val settings = saved("work", "side")
        val first = codex(settings)
        first.accounts.move(first.accounts[2], 0)

        first.accounts.add(login("new"))

        assertEquals(listOf("side", "default", "work", "new"), codex(settings).accounts.all.map { it.accountId })
    }

    @Test
    fun `should put a login last when it is moved past the end`() {
        val codex = codex(saved("work", "side"))

        codex.accounts.move(codex.accounts[0], 99)

        assertEquals(listOf("work", "side", "default"), codex.accounts.all.map { it.accountId })
    }
}
