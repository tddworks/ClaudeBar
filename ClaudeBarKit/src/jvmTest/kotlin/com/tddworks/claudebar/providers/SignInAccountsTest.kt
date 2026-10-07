package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DefinitionError
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File
import java.util.UUID

/**
 * *Sign in with browser*: the definition's login runs into a new folder, and the provider
 * checks it as *Choose Signed-in Folder* does. ClaudeBar remembers that it made the folder, so
 * *Remove* takes the folder with it; a folder the person chose is theirs.
 */
class SignInAccountsTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun stub(dataSourceKind: String? = null) = StubbedProvider("codex", dataSourceKind).also { stubs += it }

    private val StubbedProvider.root: String get() = "$home/sign-in-accounts"

    /** A login that writes a Codex `auth.json` into the folder it is given. */
    private fun StubbedProvider.codexLogin(email: String?, accountId: String = "work") = signIn(ScriptedSignIn { _, folder ->
        // The vendor's CLI writes its login into the folder it was given.
        File(folder).mkdirs()
        if (email != null) writeCodexLogin(File(folder), email, accountId)
    })

    private fun StubbedProvider.signInTo(codex: Provider, email: String?) =
        runBlocking { codex.accounts.signIn(codexLogin(email), root) }

    // Signing in

    @Test
    fun `should add the login the new folder holds when the person signs in with the browser`() {
        val stub = stub()
        val codex = stub.makeProvider("codex")

        val added = stub.signInTo(codex, "work@example.com").done()

        val folder = added.folder!!
        assertEquals("work@example.com", added.email)
        assertEquals("work", added.values["chatgptAccountId"])
        assertEquals(AccountOrigin.SIGN_IN, folder.madeBy)
        assertEquals("codex", File(folder.path).parentFile.name)
        assertEquals(AccountOrigin.SIGN_IN, stub.settings.accounts("codex").first().madeBy)
    }

    @Test
    fun `should add no login and leave no folder when sign-in ends without a login`() {
        val stub = stub()
        val codex = stub.makeProvider("codex")

        assertTrue(stub.signInTo(codex, null) is Outcome.Refused)

        assertTrue(stub.folders.all.isEmpty())
        assertEquals(1, codex.accounts.size)
    }

    @Test
    fun `should leave no new folder when the person signs in to a login already listed`() {
        val stub = stub()
        val codex = stub.makeProvider("codex")
        stub.signInTo(codex, "work@example.com").done()

        assertTrue(stub.signInTo(codex, "work@example.com") is Outcome.Refused)

        assertEquals(1, stub.folders.all.size)
    }

    // Which folder goes with an account

    @Test
    fun `should remove the folder with its login when ClaudeBar made it by signing in`() {
        val folder = SignedInFolder.forSignIn("codex", "/tmp/sign-in-accounts")

        assertTrue(folder.goesWithAccount)
    }

    @Test
    fun `should keep a folder the person chose when its login is removed`() {
        val chosen = SignedInFolder("/tmp/sign-in-accounts/codex/${UUID.randomUUID()}", AccountOrigin.FOLDER)

        assertFalse(chosen.goesWithAccount)
    }

    @Test
    fun `should never delete a signed-in folder ClaudeBar did not name`() {
        val renamed = SignedInFolder("/Users/me/.codex", AccountOrigin.SIGN_IN)

        assertFalse(renamed.goesWithAccount)
    }

    // Adding and removing

    @Test
    fun `should remember a login once it is added`() {
        val stub = stub()
        val codex = stub.makeProvider("codex")
        val work = ProviderAccountConfig("a", "", "w@example.com", probeConfig = mapOf("codexHome" to "/tmp/a", "chatgptAccountId" to "a"))

        codex.accounts.add(work)

        assertEquals(listOf(work), stub.settings.accounts("codex"))
    }

    @Test
    fun `should delete the folder ClaudeBar made when its signed-in login is removed`() {
        val stub = stub()
        val codex = stub.makeProvider("codex")
        val added = stub.signInTo(codex, "work@example.com").done()

        codex.accounts.remove(added)

        assertTrue(stub.folders.all.isEmpty())
        assertTrue(stub.settings.accounts("codex").isEmpty())
    }

    @Test
    fun `should keep the person's folder when its login is removed`() {
        val stub = stub()
        val folder = File(stub.home, UUID.randomUUID().toString())
        stub.writeCodexLogin(folder, "me@example.com", "me")
        stub.folders.create(folder.path)
        val codex = stub.makeProvider("codex")
        val added = codex.accounts.add(signedInAt = folder.path).done()

        codex.accounts.remove(added)

        assertTrue(stub.folders.exists(folder.path))
    }

    // Signing in again

    @Test
    fun `should sign in again in the folder ClaudeBar made and then show fresh usage`() {
        val stub = stub(dataSourceKind = "api")
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":10}}}""")
        val codex = stub.makeProvider("codex")
        val added = stub.signInTo(codex, "work@example.com").done()
        val again = ScriptedSignIn()

        runBlocking { codex.accounts.signInAgain(added, stub.signIn(again)) }.done()
        val usage = codex.refreshNow(added).usage()

        assertEquals(added.folder?.path, again.launches.single().second)
        assertEquals(90.0, usage.sessionQuota?.percentRemaining)
        assertTrue(stub.folders.exists(added.folder!!.path))
    }

    @Test
    fun `should refuse to sign in again in a folder the person chose`() {
        val stub = stub()
        val folder = File(stub.home, "mine")
        stub.writeCodexLogin(folder, "me@example.com", "me")
        val codex = stub.makeProvider("codex")
        val added = codex.accounts.add(signedInAt = folder.path).done()
        val again = ScriptedSignIn()

        assertTrue(runBlocking { codex.accounts.signInAgain(added, stub.signIn(again)) } is Outcome.Refused)

        assertTrue(again.launches.isEmpty())
    }

    // The ways to add, from the definition

    @Test
    fun `should offer Codex and Claude logins by browser sign-in first, then by choosing a folder`() {
        assertEquals(listOf(AddAccountWay.SIGN_IN, AddAccountWay.FOLDER), TestDefinitions.builtIn("codex").accounts?.ways)
        assertEquals(listOf(AddAccountWay.SIGN_IN, AddAccountWay.FOLDER), TestDefinitions.builtIn("claude").accounts?.ways)
    }

    @Test
    fun `should sign Claude in with its own config folder and no inherited API key`() {
        val signIn = TestDefinitions.builtIn("claude").accounts?.signIn!!

        assertEquals(listOf("auth", "login", "--claudeai"), signIn.args)
        assertEquals("CLAUDE_CONFIG_DIR", signIn.homeVariable)
        assertTrue("ANTHROPIC_API_KEY" in signIn.unset)
    }

    @Test
    fun `should refuse a provider whose browser sign-in has no way to check the folder`() {
        val json = """{ "signIn": { "cli": "x", "args": [], "homeVariable": "X_HOME" } }"""

        assertThrows<DefinitionError> { ProviderDefinition.Accounts.from(Json.parseToJsonElement(json)) }
    }
}
