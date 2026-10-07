package com.tddworks.claudebar.providers

import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The logins added beside a provider's default one, in settings.json. */
class JSONSettingsRepositoryMultiAccountTest {
    private val store = temporarySettingsFile()
    private val repo = JsonProviderSettings(store, MemoryLegacyStore())

    private fun account(
        accountId: String,
        label: String? = null,
        email: String? = null,
        organization: String? = null,
        probeConfig: Map<String, String> = emptyMap(),
    ) = ProviderAccountConfig(accountId, label ?: accountId.replaceFirstChar { it.uppercase() }, email, organization, probeConfig)

    // Backward Compatibility

    @Test
    fun `should have no added logins for a provider never set up`() {
        assertTrue(repo.accounts("claude").isEmpty())
    }

    @Test
    fun `should keep a provider's other settings when a login is added`() {
        repo.setEnabled(false, "claude")
        repo.addAccount(account("personal"), "claude")

        assertEquals(false, repo.isEnabled("claude"))
    }

    // Adding

    @Test
    fun `should remember an added login and its name`() {
        repo.addAccount(account("personal", label = "Personal"), "claude")

        val accounts = repo.accounts("claude")
        assertEquals(1, accounts.size)
        assertEquals("personal", accounts.first().accountId)
        assertEquals("Personal", accounts.first().label)
    }

    @Test
    fun `should keep added logins in the order they were added`() {
        repo.addAccount(account("personal"), "claude")
        repo.addAccount(account("work"), "claude")

        assertEquals(listOf("personal", "work"), repo.accounts("claude").map { it.accountId })
    }

    @Test
    fun `should remember everything about an added login`() {
        val original = account(
            "work", label = "Work - Acme", email = "dev@acme.example", organization = "Acme",
            probeConfig = mapOf("profile" to "acme", "tokenEnvVar" to "ACME_TOKEN"),
        ).made(AccountOrigin.SIGN_IN)
        repo.addAccount(original, "claude")

        assertEquals(original, repo.accounts("claude").first())
    }

    @Test
    fun `should replace a login added again rather than list it twice`() {
        repo.addAccount(account("personal", label = "Old"), "claude")
        repo.addAccount(account("personal", label = "New"), "claude")

        val accounts = repo.accounts("claude")
        assertEquals(1, accounts.size)
        assertEquals("New", accounts.first().label)
    }

    @Test
    fun `should keep each provider's added logins apart`() {
        repo.addAccount(account("personal"), "claude")
        repo.addAccount(account("work"), "codex")

        assertEquals(listOf("personal"), repo.accounts("claude").map { it.accountId })
        assertEquals(listOf("work"), repo.accounts("codex").map { it.accountId })
    }

    // Updating

    @Test
    fun `should change a login in place, keeping its position`() {
        repo.addAccount(account("personal", label = "Personal"), "claude")
        repo.addAccount(account("work", label = "Work"), "claude")

        repo.updateAccount(account("personal", label = "Home"), "claude")

        val accounts = repo.accounts("claude")
        assertEquals(listOf("personal", "work"), accounts.map { it.accountId })
        assertEquals("Home", accounts.first().label)
    }

    @Test
    fun `should leave the logins as they are when changing one that does not exist`() {
        repo.addAccount(account("personal"), "claude")
        repo.updateAccount(account("ghost", label = "Ghost"), "claude")

        assertEquals(listOf("personal"), repo.accounts("claude").map { it.accountId })
    }

    // Removing

    @Test
    fun `should remove only the named login`() {
        repo.addAccount(account("personal"), "claude")
        repo.addAccount(account("work"), "claude")

        repo.removeAccount("personal", "claude")

        assertEquals(listOf("work"), repo.accounts("claude").map { it.accountId })
    }

    @Test
    fun `should leave the logins as they are when removing one that does not exist`() {
        repo.addAccount(account("personal"), "claude")
        repo.removeAccount("ghost", "claude")

        assertEquals(listOf("personal"), repo.accounts("claude").map { it.accountId })
    }

    @Test
    fun `should leave the provider with only its default login once the last added one is removed`() {
        repo.addAccount(account("personal"), "claude")
        repo.removeAccount("personal", "claude")

        assertTrue(repo.accounts("claude").isEmpty())
        assertNull(store.read("providers.claude.accounts"))
    }

    // The default login's name

    @Test
    fun `should remember the default login's name per provider, and forget it when cleared`() {
        repo.setDefaultAccountLabel("Personal", "claude")
        assertEquals("Personal", repo.defaultAccountLabel("claude"))
        assertNull(repo.defaultAccountLabel("codex"))

        repo.setDefaultAccountLabel(null, "claude")
        assertNull(repo.defaultAccountLabel("claude"))
    }

    // Key Pattern

    @Test
    fun `should keep the default login's name under its provider in settings-json`() {
        repo.setDefaultAccountLabel("Personal", "claude")

        assertEquals("Personal", store.string("providers.claude.defaultAccountLabel"))
    }

    @Test
    fun `should keep added logins under their provider in settings-json`() {
        repo.addAccount(account("personal", label = "Personal"), "claude")

        val raw = store.read("providers.claude.accounts") as? JsonArray
        assertEquals(1, raw?.size)
        assertEquals("personal", (raw?.first() as? JsonObject)?.get("accountId")?.jsonPrimitive?.content)
    }

    @Test
    fun `should have no added logins when settings-json lists none`() {
        store.write("providers.claude.accounts", JsonArray(emptyList()))

        assertTrue(repo.accounts("claude").isEmpty())
    }

    @Test
    fun `should skip a broken login in settings-json and keep the rest`() {
        store.write(
            "providers.claude.accounts",
            Json.parseToJsonElement("""[{"not":"an account"},{"accountId":"personal","label":"Personal","probeConfig":{}}]"""),
        )

        assertEquals(listOf("personal"), repo.accounts("claude").map { it.accountId })
    }

    // Persistence Across Instances

    @Test
    fun `should remember added logins and the default login's name across restarts`() {
        repo.addAccount(account("personal", label = "Personal"), "claude")
        repo.setDefaultAccountLabel("Me", "claude")

        val reopened = JsonProviderSettings(SettingsFile(store.path), MemoryLegacyStore())

        assertEquals(listOf("personal"), reopened.accounts("claude").map { it.accountId })
        assertEquals("Me", reopened.defaultAccountLabel("claude"))
    }
}
