package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant
import java.util.Base64

/**
 * Codex's added accounts (#326) and its passive background (#216), all from `codex.json`: the
 * default login, and each login added by its folder.
 */
class CodexAccountsTest {
    private val stub = StubbedProvider("codex")

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private val home = File(stub.home)

    // The default login stays passive until checked (#216)

    @Test
    fun `should not start Codex in the background, and ask to click Refresh or Connect, before the person has checked it once (#216)`() {
        stub.answerRPC(USAGE)
        val codex = stub.makeProvider("codex")

        assertTrue(codex.refreshPlain(RefreshKind.BACKGROUND) is RefreshOutcome.Failed)

        assertEquals(0, stub.launches.size)
        assertEquals(true, codex.defaultAccount.lastError?.message?.contains("Click Refresh or Connect"))
    }

    @Test
    fun `should not start an unchecked Codex when the person opens the popover (#216)`() {
        stub.answerRPC(USAGE)
        val codex = stub.makeProvider("codex")

        assertTrue(codex.refreshPlain(RefreshKind.PASSIVE) is RefreshOutcome.Failed)

        assertEquals(0, stub.launches.size)
    }

    @Test
    fun `should keep refreshing Codex in the background once the person has refreshed it by hand`() {
        stub.answerRPC(USAGE)
        val codex = stub.makeProvider("codex")

        codex.refreshPlain().usage()
        val background = codex.refreshPlain(RefreshKind.BACKGROUND).usage()

        assertEquals(true, stub.settings.isOn("verifiedAtLeastOnce", "codex"))
        assertEquals(80.0, background.quota(QuotaType.Session)?.percentRemaining)
        assertEquals(2, stub.launches.size)
    }

    @Test
    fun `should leave the Codex CLI unchecked when the login is read through the API`() {
        val stub = StubbedProvider("codex", "api")
        try {
            stub.writeCodexAuth(accountId = "account")
            stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":10}}}""")

            stub.makeProvider("codex").refreshPlain().usage()

            assertNull(stub.settings.isOn("verifiedAtLeastOnce", "codex"))
        } finally {
            stub.cleanUp()
        }
    }

    @Test
    fun `should ask to sign in, without starting Codex, when there is no Codex login`() {
        File(home, ".codex/auth.json").delete()
        stub.answerRPC(USAGE)
        stub.answerTerminal("5h limit: 99% left")

        val outcome = stub.makeProvider("codex").refreshPlain()

        assertEquals(RefreshOutcome.Failed(UsageError.AuthenticationRequired), outcome)
        assertEquals(0, stub.launches.size)
    }

    @Test
    fun `should show a Keychain login's email as the Codex CLI reports it`() {
        stub.answerRPC(USAGE, account = """{"id":3,"result":{"account":{"type":"chatgpt","email":"keychain@example.com"}}}""")

        val usage = stub.makeProvider("codex").refreshPlain().usage()

        assertEquals("keychain@example.com", usage.accountEmail)
        assertEquals(80.0, usage.lowestQuota?.percentRemaining)
    }

    // Added accounts

    @Test
    fun `should run Codex in an added login's own folder with file credentials only, and no API key`() {
        val folder = writeLogin("work", email = "work@example.com", accountId = "work")
        stub.answerRPC(USAGE)
        val (product, account) = stub.makeAdded("codex", config("a", folder, accountId = "work"))

        product.refreshNow(account, RefreshKind.BACKGROUND)

        val launch = stub.launches.lastOrNull()
        assertNotNull(launch)
        assertEquals(folder.path, launch!!.second?.get("CODEX_HOME"))
        assertNull(launch.second?.get("OPENAI_API_KEY"))
        assertTrue(launch.first.contains("""cli_auth_credentials_store="file""""))
        assertNull(stub.settings.isOn("verifiedAtLeastOnce", "codex"))
    }

    @Test
    fun `should keep each added login's own id, name and usage, and one login's failure its own (#326)`() {
        val a = writeLogin("a", email = "a@example.com", accountId = "a")
        stub.answerRPC(USAGE)
        val (firstProduct, first) = stub.makeAdded("codex", config("a", a, accountId = "a", email = "a@example.com"))
        val (secondProduct, second) = stub.makeAdded(
            "codex", config("b", File(home, "signed-out"), accountId = "b", email = "b@example.com"),
        )

        val usage = firstProduct.refreshNow(first).usage()
        assertTrue(secondProduct.refreshNow(second) is RefreshOutcome.Failed)

        assertEquals("codex.a", first.id)
        assertEquals("codex.b", second.id)
        assertEquals("a@example.com", firstProduct.lineupName(first))
        assertEquals("b@example.com", secondProduct.lineupName(second))
        assertEquals("codex.a", usage.providerId)
        assertEquals("codex.a", usage.quotas.firstOrNull()?.providerId)
        assertNull(second.snapshot)
        assertNotNull(second.lastError)
    }

    @Test
    fun `should show the login's email whether Codex is read over RPC or the API`() {
        val folder = writeLogin("work", email = "signed-in@example.com", accountId = "work")
        stub.answerRPC(USAGE)
        stub.answerHTTP("""{"rate_limit":{"primary_window":{"used_percent":10}}}""")
        val (product, account) = stub.makeAdded("codex", config("a", folder, accountId = "work"))

        val viaRPC = product.refreshNow(account).usage()
        product.configuration.use("api")
        val viaAPI = product.refreshNow(account).usage()

        assertEquals("signed-in@example.com", viaRPC.accountEmail)
        assertEquals("signed-in@example.com", viaAPI.accountEmail)
    }

    @Test
    fun `should be unavailable, without starting Codex, when an added login's folder is signed in to another account`() {
        val folder = writeLogin("work", email = "other@example.com", accountId = "other")
        stub.answerRPC(USAGE)
        stub.cli.located = { "/usr/local/bin/codex" }
        val (product, account) = stub.makeAdded("codex", config("a", folder, accountId = "original"))

        assertFalse(runBlocking { product.isAvailable(account) })
        assertTrue(product.refreshNow(account) is RefreshOutcome.Failed)

        assertEquals(0, stub.launches.size)
        assertEquals(true, account.lastError?.message?.contains("original account"))
    }

    // Adding an account by its folder

    @Test
    fun `should add two folders as two logins with their own emails`() {
        val a = writeLogin("account a", email = "a@example.com", accountId = "account-a")
        val b = writeLogin("account b", email = "b@example.com", accountId = "account-b")
        val codex = stub.makeProvider("codex")

        val first = codex.accounts.add(signedInAt = a.path).done()
        val second = codex.accounts.add(signedInAt = b.path).done()

        assertEquals("a@example.com", first.email)
        assertEquals("b@example.com", second.email)
        assertNotEquals(first.accountId, second.accountId)
        assertEquals("account-a", first.values["chatgptAccountId"])
        assertEquals(a.canonicalPath, first.values["codexHome"])
        assertEquals(AccountOrigin.FOLDER, first.madeBy)
    }

    @Test
    fun `should refuse a folder whose login is already listed`() {
        val a = writeLogin("a", email = "same@example.com", accountId = "same")
        val b = writeLogin("b", email = "same@example.com", accountId = "same")
        val codex = stub.makeProvider("codex")
        codex.accounts.add(signedInAt = a.path).done()

        assertEquals(Outcome.Refused("This Codex account is already listed."), codex.accounts.add(signedInAt = b.path))
    }

    @Test
    fun `should add one email in two workspaces as two logins`() {
        val a = writeLogin("a", email = "same@example.com", accountId = "workspace-a")
        val b = writeLogin("b", email = "same@example.com", accountId = "workspace-b")
        val codex = stub.makeProvider("codex")

        val first = codex.accounts.add(signedInAt = a.path).done()
        val second = codex.accounts.add(signedInAt = b.path).done()

        assertNotEquals(first.values["chatgptAccountId"], second.values["chatgptAccountId"])
    }

    @Test
    fun `should refuse a folder with no ChatGPT login and add nothing`() {
        val codex = stub.makeProvider("codex")

        assertEquals(
            Outcome.Refused("No ChatGPT account found in this folder. Sign in with Codex using file credential storage, then choose the folder again."),
            codex.accounts.add(signedInAt = File(home, "missing").path),
        )
        assertEquals(1, codex.accounts.size)
    }

    @Test
    fun `should refuse a folder holding the default login`() {
        stub.writeCodexAuth(accountId = "me")
        val copy = writeLogin("copy", email = "me@example.com", accountId = "me")
        val codex = stub.makeProvider("codex")

        assertEquals(Outcome.Refused("This Codex account is already listed."), codex.accounts.add(signedInAt = copy.path))
    }

    @Test
    fun `should bring saved logins back under one Codex provider, each enabled or disabled on its own`() {
        val a = writeLogin("a", email = "a@example.com", accountId = "a")
        val b = writeLogin("b", email = "b@example.com", accountId = "b")
        val before = stub.makeProvider("codex")
        before.accounts.add(signedInAt = a.path).done()
        before.accounts.add(signedInAt = b.path).done()

        val codex = stub.makeProvider("codex", accounts = stub.settings.accounts("codex"))
        val added = codex.accounts.drop(1)
        added[0].isEnabled = false

        assertEquals(3, codex.accounts.size)
        assertEquals("codex", codex.defaultAccount.id)
        assertEquals(listOf("a@example.com", "b@example.com"), added.map(codex::lineupName))
        assertEquals(3, codex.accounts.map { it.id }.toSet().size)
        assertTrue(added[1].isEnabled)
        assertEquals(false, stub.settings.isEnabled(added[0].id, true))
    }

    // One provider, many logins

    @Test
    fun `should read added logins over RPC and the API only, from their own folder and account`() {
        val folder = writeLogin("work", email = "work@example.com", accountId = "work")
        val codex = stub.makeProvider("codex", accounts = listOf(config("a", folder, accountId = "work")))

        val defaultKinds = codex.dataSources(codex.defaultAccount).map { it.definition.kind }
        val addedSources = codex.dataSources(codex.accounts[1])

        assertEquals(listOf("rpc", "api", "tty"), defaultKinds)
        assertEquals(listOf("rpc", "api"), addedSources.map { it.definition.kind })
        assertNull(addedSources.firstOrNull()?.definition?.fallback)
        assertEquals(listOf("${folder.path}/auth.json"), addedSources.firstOrNull()?.definition?.requiresFiles)
        assertEquals("work", addedSources.firstOrNull()?.definition?.identity?.equals)
    }

    @Test
    fun `should apply the person's data source choice to every login`() {
        val folder = writeLogin("work", email = "work@example.com", accountId = "work")
        val codex = stub.makeProvider("codex", accounts = listOf(config("a", folder, accountId = "work")))

        codex.configuration.use("api")

        assertEquals("api", codex.configuration.activeKind)
        assertEquals("api", stub.settings.dataSourceKind("codex"))
    }

    @Test
    fun `should not add a login whose saved values are incomplete`() {
        val codex = stub.makeProvider("codex")

        val added = codex.accounts.add(ProviderAccountConfig("a", "", probeConfig = mapOf("codexHome" to "/tmp/x")))

        assertNull(added)
        assertEquals(1, codex.accounts.size)
    }

    @Test
    fun `should list a login once and keep the default login when asked to remove it`() {
        val folder = writeLogin("work", email = "work@example.com", accountId = "work")
        val codex = stub.makeProvider("codex")
        val work = config("a", folder, accountId = "work")

        val first = codex.accounts.add(work)
        assertNotNull(first)
        val again = codex.accounts.add(work)
        codex.accounts.remove(codex.defaultAccount)
        codex.accounts.remove(first!!)

        assertNull(again)
        assertEquals(listOf("codex"), codex.accounts.map { it.id })
    }

    @Test
    fun `should show the worst enabled login's status and pick the login with the most left as best`() {
        val stub = StubbedProvider("codex", "api")
        try {
            stub.writeCodexAuth(accountId = "me")
            val folder = writeLogin("work", email = "work@example.com", accountId = "work", root = File(stub.home))
            val codex = stub.makeProvider("codex", accounts = listOf(config("a", folder, accountId = "work")))
            val me = codex.defaultAccount
            val work = codex.accounts[1]
            stub.http.answer = { call ->
                val used = when (call.headers.entries.firstOrNull { it.key.equals("ChatGPT-Account-Id", true) }?.value) {
                    "me" -> 90
                    "work" -> 10
                    else -> null
                }
                if (used == null) Response(500, body = ByteArray(0))
                else Response(200, body = """{"rate_limit":{"primary_window":{"used_percent":$used}}}""".encodeToByteArray())
            }

            codex.refreshNow(me).usage()
            codex.refreshNow(work).usage()

            assertEquals(QuotaStatus.CRITICAL, me.status)
            assertEquals(QuotaStatus.HEALTHY, work.status)
            assertEquals(QuotaStatus.CRITICAL, codex.status)
            assertSame(work, codex.accounts.best)

            me.isEnabled = false

            assertEquals(QuotaStatus.HEALTHY, codex.status)
        } finally {
            stub.cleanUp()
        }
    }

    // Helpers

    private fun config(id: String, folder: File, accountId: String, email: String? = null) = ProviderAccountConfig(
        id, "", email,
        probeConfig = mapOf("codexHome" to folder.path, "chatgptAccountId" to accountId),
    )

    /** A Codex folder signed in with file credentials: `auth.json` with an account id and an id token carrying the email. */
    private fun writeLogin(name: String, email: String, accountId: String, root: File = home): File {
        val folder = File(root, name).also { it.mkdirs() }
        val claims = Base64.getEncoder().encodeToString("""{"email":"$email"}""".toByteArray()).replace("=", "")
        val jwt = "header.$claims.signature"
        File(folder, "auth.json").writeText(
            """{"tokens":{"access_token":"token-$name","refresh_token":"refresh-$name","account_id":"$accountId","id_token":"$jwt"},"last_refresh":"${Instant.now().epochSecond.let(Instant::ofEpochSecond)}"}""",
        )
        return folder
    }

    private companion object {
        const val USAGE = """{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":20}}}}"""
    }
}
