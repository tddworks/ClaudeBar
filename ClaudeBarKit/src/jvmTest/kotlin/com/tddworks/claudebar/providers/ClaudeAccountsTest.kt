package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.IdentityField
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.Recovery
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.security.MessageDigest

/**
 * Claude's added accounts, all from `claude.json`: a second login lives in its own config folder
 * (`CLAUDE_CONFIG_DIR`), runs the same data sources filled with that folder, and is told apart
 * by the email its `.claude.json` holds. The default login is untouched.
 */
class ClaudeAccountsTest {
    private val claude = ClaudeHarness()

    @AfterEach
    fun cleanUp() = claude.cleanUp()

    private fun api() = InMemoryProviderSettings(dataSourceKinds = mapOf("claude" to "api"))

    private fun config(id: String, folder: File, email: String) = ProviderAccountConfig(
        accountId = id, label = "", email = email,
        probeConfig = mapOf("configDirectory" to folder.path, "loginEmail" to email, "credentialService" to "fixture-$id"),
    )

    /** Answers the usage API by bearer token: each login sees its own numbers. */
    private fun answerByToken(used: Map<String, Int>) {
        claude.answer { call ->
            val token = call.claudeAuthorization?.removePrefix("Bearer ") ?: ""
            claudeResponse(200, body = """{ "five_hour": { "utilization": ${used[token] ?: 0} } }""")
        }
    }

    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    // Each login reads its own folder

    @Test
    fun `should show an added login the usage of its own key and its own email`() {
        claude.writeCredentials(accessToken = "default-token")
        claude.writeClaudeConfig(email = "me@example.com")
        val work = claude.writeLogin("work", email = "work@example.com", token = "work-token")
        answerByToken(mapOf("default-token" to 20, "work-token" to 70))
        val provider = claude.provider(settings = api(), accounts = listOf(config("w", work, "work@example.com")))
        val me = provider.accounts[0]
        val added = provider.accounts[1]

        val mine = provider.refreshNow(me).usage()
        val theirs = provider.refreshNow(added).usage()

        assertEquals("claude.w", added.id)
        assertEquals(80.0, mine.sessionQuota?.percentRemaining)
        assertEquals(30.0, theirs.sessionQuota?.percentRemaining)
        assertEquals("work@example.com", theirs.accountEmail)
        assertEquals("claude.w", theirs.providerId)
    }

    @Test
    fun `should fail closed for a folder now signed in to someone else while the others keep their usage`() {
        claude.writeCredentials(accessToken = "default-token")
        val work = claude.writeLogin("work", email = "someone-else@example.com", token = "work-token")
        answerByToken(mapOf("default-token" to 20, "work-token" to 70))
        val provider = claude.provider(settings = api(), accounts = listOf(config("w", work, "work@example.com")))
        val me = provider.accounts[0]
        val added = provider.accounts[1]

        provider.refreshNow(me)
        val outcome = provider.refreshNow(added)

        assertTrue(outcome is RefreshOutcome.Failed, "expected a failure, got $outcome")
        assertNull(added.snapshot)
        assertTrue(added.lastError?.message?.contains("Reconnect the original Claude account") == true, "got ${added.lastError}")
        assertEquals(80.0, me.snapshot?.sessionQuota?.percentRemaining)
    }

    @Test
    fun `should run the CLI for an added login in its own folder without the default login's keys`() {
        val sources = TestDefinitions.builtIn("claude").dataSourcesForAccount(mapOf(
            "configDirectory" to "/Users/me/claude-work", "loginEmail" to "work@example.com", "credentialService" to "svc",
        ))

        for (kind in listOf("cli", "cliCost")) {
            val source = sources.first { it.kind == kind }
            val call = (source.fetch as? Fetch.Cli)?.call
            assertNotNull(call, "$kind is not a CLI")
            assertEquals("/Users/me/claude-work", call!!.environment.set["CLAUDE_CONFIG_DIR"])
            assertTrue("ANTHROPIC_API_KEY" in call.environment.unset)
            assertTrue("CLAUDE_CODE_OAUTH_TOKEN" in call.environment.unset)
            assertEquals(PathPattern("/Users/me/claude-work/.claude.json"), source.context["account"]?.path)
            assertEquals(IdentityField.ContextValue("account", "email"), source.identity?.field)
            assertEquals("work@example.com", source.identity?.equals)
        }
    }

    @Test
    fun `should grant folder trust in the added login's own config`() {
        val sources = TestDefinitions.builtIn("claude").dataSourcesForAccount(mapOf(
            "configDirectory" to "/Users/me/claude-work", "loginEmail" to "work@example.com", "credentialService" to "svc",
        ))
        val cli = sources.first { it.kind == "cli" }

        val recovery = cli.recover["folderTrustRequired"] as? Recovery.PatchJSONFile
        assertNotNull(recovery, "no folder-trust recovery")
        assertEquals("/Users/me/claude-work/.claude.json", recovery!!.path)
    }

    @Test
    fun `should leave the default login as it was when accounts are added`() {
        val cli = TestDefinitions.builtIn("claude").dataSource("cli")!!

        assertNull(cli.identity)
        assertEquals(PathPattern("\${CLAUDE_CONFIG_DIR:-~}/.claude.json"), cli.context["account"]?.path)
    }

    // Guest passes are the default login's

    @Test
    fun `should give guest passes to the default login only`() {
        val work = claude.writeLogin("work", email = "work@example.com", token = "work-token")
        val provider = claude.provider(
            settings = api(),
            accounts = listOf(config("w", work, "work@example.com")),
            guestPasses = GuestPasses(ClaudeNoGuestPasses),
        )

        assertNull(provider.accounts[1].guestPasses)
        assertNotNull(provider.defaultAccount.guestPasses)
    }

    // Add Account: choosing a signed-in folder

    @Test
    fun `should save the folder, its email and its keychain service when the person chooses a signed-in folder`() {
        val settings = InMemoryProviderSettings()
        val work = claude.writeLogin("work", email = "work@example.com")
        val provider = claude.provider(settings = settings)

        val added = provider.accounts.add(signedInAt = work.path).done()

        val folder = added.values["configDirectory"]!!
        assertEquals("work@example.com", added.email)
        assertEquals("work@example.com", added.values["loginEmail"])
        assertEquals("Claude Code-credentials-${sha256(folder).take(8)}", added.values["credentialService"])
        assertEquals(listOf(added.accountId), settings.accounts("claude").map { it.accountId })
    }

    @Test
    fun `should not add the same login twice`() {
        val work = claude.writeLogin("work", email = "work@example.com")
        val again = claude.writeLogin("work-again", email = "work@example.com")
        val provider = claude.provider()
        provider.accounts.add(signedInAt = work.path).done()

        assertTrue(provider.accounts.add(signedInAt = work.path) is Outcome.Refused)
        assertTrue(provider.accounts.add(signedInAt = again.path) is Outcome.Refused)
        assertEquals(2, provider.accounts.size)
    }

    @Test
    fun `should refuse a folder with an email but no key as a login`() {
        val folder = claude.writeLogin("half", email = "half@example.com")
        File(folder, ".credentials.json").delete()
        val provider = claude.provider()

        assertTrue(provider.accounts.add(signedInAt = folder.path) is Outcome.Refused)
    }

    @Test
    fun `should not add the default login again from another folder`() {
        claude.writeClaudeConfig(email = "me@example.com")
        val copy = claude.writeLogin("copy", email = "me@example.com")
        val provider = claude.provider()

        assertTrue(provider.accounts.add(signedInAt = copy.path) is Outcome.Refused)
    }
}

/** A guest-pass source that is never asked. */
internal object ClaudeNoGuestPasses : GuestPassSource {
    override suspend fun isAvailable(): Boolean = false
    override suspend fun fetch(): GuestPass = throw IllegalStateException("not asked in this test")
}
