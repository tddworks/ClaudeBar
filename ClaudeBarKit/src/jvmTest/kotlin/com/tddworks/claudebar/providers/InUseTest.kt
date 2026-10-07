package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant

/**
 * *In use* — which login new terminal sessions start with. Two Codex logins are *me* (the
 * plain login) and *work* (an added folder); choosing one writes only its folder, and only new
 * sessions follow it.
 */
class InUseTest {
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    private fun twoLogins() = InUseFixture.twoLogins().also { stubs += it.stub }

    // Offered, or not

    @Test
    fun `should offer In use, with the plain login in use, when the provider's CLI starts on a login's folder`() {
        val (_, codex) = twoLogins()

        val inUse = codex.inUse!!
        assertSame(codex.defaultAccount, inUse.login)
        assertEquals(TerminalCommand("codex", "CODEX_HOME"), inUse.command)
    }

    @Test
    fun `should offer no In use when the provider's CLI has no login folder`() {
        val stub = StubbedProvider("gemini").also { stubs += it }

        assertNull(stub.makeProvider("gemini").inUse)
    }

    @Test
    fun `should offer no In use when there is nowhere to record the choice`() {
        val stub = StubbedProvider("codex").also { stubs += it }

        val codex = stub.makeProvider("codex", loginsInUse = null)

        assertNull(codex.inUse)
    }

    @Test
    fun `should offer the plain login and every folder login, and no choice when there is only one`() {
        val (_, codex, work) = twoLogins()
        val alone = StubbedProvider("codex").also { stubs += it }

        assertEquals(listOf(codex.defaultAccount.id, work.id), codex.inUse?.logins?.map { it.id })
        assertEquals(true, codex.inUse?.offersChoice)
        assertEquals(false, alone.makeProvider("codex").inUse?.offersChoice)
    }

    // Choosing

    @Test
    fun `should put a chosen login in use and record only its folder`() {
        val (stub, codex, work) = twoLogins()

        codex.inUse!!.use(work).done()

        assertEquals(true, codex.inUse?.isInUse(work))
        assertNotEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
        assertEquals(work.folder?.path, stub.loginsInUse.folder("codex"))
    }

    @Test
    fun `should share the login in use between two providers that run the same CLI`() {
        val (stub, codex, work) = twoLogins()
        // A second product running the same CLI, on the same record.
        val other = stub.makeProvider("codex", stub.settings.accounts("codex"))

        codex.inUse!!.use(work).done()
        other.inUse!!.use(other.defaultAccount).done()

        assertNull(stub.loginsInUse.folder("codex"))
        val again = stub.makeProvider("codex", stub.settings.accounts("codex"))
        assertSame(again.defaultAccount, again.inUse?.login)
        assertEquals("codex", codex.inUse?.command?.name)
    }

    @Test
    fun `should keep the login in use after a relaunch`() {
        val (stub, codex, work) = twoLogins()
        codex.inUse!!.use(work).done()

        val again = stub.makeProvider("codex", stub.settings.accounts("codex"))

        assertEquals(work.accountId, again.inUse?.login?.accountId)
    }

    @Test
    fun `should clear the record when the person chooses the plain login`() {
        val (stub, codex, work) = twoLogins()
        codex.inUse!!.use(work).done()

        codex.inUse!!.use(codex.defaultAccount).done()

        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
        assertNull(stub.loginsInUse.folder("codex"))
    }

    @Test
    fun `should go back to the plain login when the login in use is removed`() {
        val (stub, codex, work) = twoLogins()
        codex.inUse!!.use(work).done()

        codex.accounts.remove(work)

        assertSame(codex.defaultAccount, codex.inUse?.login)
        assertNull(stub.loginsInUse.folder("codex"))
    }

    @Test
    fun `should use the plain login when the record names a folder no login has`() {
        val (stub) = twoLogins()
        stub.loginsInUse.use("/tmp/gone", "codex")

        val codex = stub.makeProvider("codex", stub.settings.accounts("codex"))

        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
    }

    @Test
    fun `should refuse to put another provider's login in use`() {
        val (_, codex) = twoLogins()
        val claudeStub = StubbedProvider("claude").also { stubs += it }
        val claude = claudeStub.makeProvider("claude")

        assertTrue(codex.inUse!!.use(claude.defaultAccount) is Outcome.Refused)
        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
    }

    @Test
    fun `should find a login by its name, its id, or default for the plain login`() {
        val (_, codex, work) = twoLogins()

        assertSame(work, codex.accounts.named("Work"))
        assertSame(work, codex.accounts.named(work.id))
        assertSame(codex.defaultAccount, codex.accounts.named("default"))
        assertNull(codex.accounts.named("someone"))
    }

    // Worth switching

    @Test
    fun `should suggest the login with more left when the login in use is low`() {
        val (stub, codex, work) = twoLogins()
        InUseFixture.usage(stub, codex, me = 92, work = 15)

        assertSame(work, codex.inUse?.worthSwitchingTo)
    }

    @Test
    fun `should suggest no switch while the login in use has room or no login has more left`() {
        val (stub, codex) = twoLogins()

        InUseFixture.usage(stub, codex, me = 40, work = 10)
        assertNull(codex.inUse?.worthSwitchingTo)

        InUseFixture.usage(stub, codex, me = 92, work = 95)
        assertNull(codex.inUse?.worthSwitchingTo)
    }

    // After each refresh: what is worth telling

    @Test
    fun `should tell the person once, not on every refresh, that a login is worth switching to`() {
        val (stub, codex, work) = twoLogins()
        InUseFixture.usage(stub, codex, me = 92, work = 15)
        val inUse = codex.inUse!!

        assertEquals(InUseNotice.WorthSwitching(codex.defaultAccount, work), inUse.review())
        assertNull(inUse.review())
    }

    @Test
    fun `should tell the person again when the login in use runs low after recovering`() {
        val (stub, codex, work) = twoLogins()
        val inUse = codex.inUse!!
        InUseFixture.usage(stub, codex, me = 92, work = 15)
        inUse.review()

        InUseFixture.usage(stub, codex, me = 30, work = 15)
        assertNull(inUse.review())
        InUseFixture.usage(stub, codex, me = 95, work = 15)

        assertEquals(InUseNotice.WorthSwitching(codex.defaultAccount, work), inUse.review())
    }

    @Test
    fun `should switch and tell the person so when Switch when low is on`() {
        val (stub, codex, work) = twoLogins()
        val inUse = codex.inUse!!
        inUse.switchWhenLow.isOn = true
        InUseFixture.usage(stub, codex, me = 95, work = 15)

        assertEquals(InUseNotice.Switched(codex.defaultAccount, work), inUse.review())
        assertEquals(true, codex.inUse?.isInUse(work))
    }
}

/** Codex with the plain login *me* and an added folder login *work*, and their usage on demand. */
internal object InUseFixture {
    data class TwoLogins(val stub: StubbedProvider, val codex: Provider, val work: Account)

    fun twoLogins(): TwoLogins {
        val stub = StubbedProvider("codex", "api")
        stub.writeCodexAuth(accountId = "me")
        val folder = File(stub.home, "work").also { it.mkdirs() }
        File(folder, "auth.json").writeText(
            """{"tokens":{"access_token":"token-work","refresh_token":"refresh-work","account_id":"work"},"last_refresh":"${Instant.now()}"}""",
        )
        val config = ProviderAccountConfig("work", "work", probeConfig = mapOf("codexHome" to folder.path, "chatgptAccountId" to "work"))
        stub.settings.addAccount(config, "codex")
        val codex = stub.makeProvider("codex", stub.settings.accounts("codex"))
        return TwoLogins(stub, codex, codex.accounts[1])
    }

    /** Both logins refreshed with these percentages used. */
    fun usage(stub: StubbedProvider, codex: Provider, me: Int, work: Int) {
        val used = mapOf("me" to me, "work" to work)
        stub.http.answer = { call ->
            val percent = used[call.headers["ChatGPT-Account-Id"]]
            if (percent == null) Response(404, body = ByteArray(0))
            else Response(200, body = """{"rate_limit":{"primary_window":{"used_percent":$percent}}}""".encodeToByteArray())
        }
        codex.refreshPlain().usage()
        codex.refreshNow(codex.accounts[1]).usage()
    }
}
