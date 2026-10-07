package com.tddworks.claudebar.activity

import com.tddworks.claudebar.providers.InUseFixture
import com.tddworks.claudebar.providers.InUseNotice
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.StubbedProvider
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException

/** *New terminal sessions*: choosing which login each CLI starts with, and the shell lines that make the choice count. */
class NewSessionsTest {
    /** The shell lines, kept in memory. */
    private class Lines : ShellLines {
        val installed = mutableSetOf<LoginShell>()
        var failing = false
        override fun lines(shell: LoginShell) = "# lines for ${shell.tag}"
        override fun file(shell: LoginShell) = "/Users/you/.${shell.tag}rc"
        override fun isInstalled(shell: LoginShell) = shell in installed
        override fun install(shell: LoginShell) {
            if (failing) throw IOException("Permission denied")
            installed += shell
        }
        override fun remove(shell: LoginShell) {
            installed -= shell
        }
    }

    private val lines = Lines()
    private val stubs = mutableListOf<StubbedProvider>()

    @AfterEach
    fun cleanUp() = stubs.forEach { it.cleanUp() }

    /** Codex with its plain login and an added folder login, *work*. */
    private fun codex(): Provider = InUseFixture.twoLogins().also { stubs += it.stub }.codex

    private fun alone(id: String): Provider = StubbedProvider(id).also { stubs += it }.makeProvider(id)

    private fun sessions(vararg products: Provider, shell: LoginShell = LoginShell.ZSH) =
        NewSessions(products.toList(), lines, shell = shell)

    @Test
    fun `should start new sessions with the chosen login at once when the shell is set up`() {
        lines.installed += LoginShell.ZSH
        val codex = codex()
        val sessions = sessions(codex)

        sessions.use(codex.accounts[1])

        assertEquals(true, codex.inUse?.isInUse(codex.accounts[1]))
        assertNull(sessions.waiting)
    }

    @Test
    fun `should hold the chosen login until the shell is set up`() {
        val codex = codex()
        val sessions = sessions(codex)

        sessions.use(codex.accounts[1])

        assertNotEquals(true, codex.inUse?.isInUse(codex.accounts[1]))
        assertTrue(sessions.isWaiting(codex))
    }

    @Test
    fun `should set up the shell and start new sessions with the held login when the person sets up`() {
        val codex = codex()
        val sessions = sessions(codex, shell = LoginShell.BASH)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        assertTrue(sessions.isSetUp)
        assertEquals(setOf(LoginShell.BASH), lines.installed)
        assertEquals(true, codex.inUse?.isInUse(codex.accounts[1]))
        assertNull(sessions.waiting)
    }

    @Test
    fun `should hand the person the shell lines and start new sessions with the held login when they set up by hand`() {
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])

        val copied = sessions.setUpByHand()

        assertEquals("# lines for zsh", copied)
        assertEquals(true, codex.inUse?.isInUse(codex.accounts[1]))
    }

    @Test
    fun `should keep the login in use as it was when the person cancels the setup`() {
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])

        sessions.cancel()

        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
        assertNull(sessions.waiting)
    }

    @Test
    fun `should start new sessions with the plain login without waiting for the shell setup`() {
        lines.installed += LoginShell.ZSH
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])
        lines.installed.clear()

        sessions.use(codex.defaultAccount)

        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
        assertNull(sessions.waiting)
    }

    @Test
    fun `should remove the shell lines and put every CLI back on its plain login when the person turns new sessions off`() {
        lines.installed += LoginShell.ZSH
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])

        sessions.turnOff()

        assertFalse(sessions.isSetUp)
        assertTrue(lines.installed.isEmpty())
        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
    }

    @Test
    fun `should name the shell file and keep the login held when the setup can't write it`() {
        lines.failing = true
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        assertEquals(true, sessions.problem?.contains("/Users/you/.zshrc"))
        assertTrue(sessions.isWaiting(codex))
    }

    // What the strip shows

    @Test
    fun `should show the login new sessions start with`() {
        val codex = codex()
        val sessions = sessions(codex)

        assertEquals(NewSessions.State.Using(codex.defaultAccount), sessions.state(codex))
    }

    @Test
    fun `should show the setup while a chosen login waits for it`() {
        val codex = codex()
        val sessions = sessions(codex)
        sessions.use(codex.accounts[1])

        assertEquals(NewSessions.State.WaitingForSetup, sessions.state(codex))
    }

    @Test
    fun `should show nothing for a provider with one login`() {
        val alone = alone("codex")
        val sessions = sessions(alone)

        assertNull(sessions.state(alone))
    }

    @Test
    fun `should name each CLI once, however many providers run it`() {
        val sessions = sessions(codex(), codex())

        assertEquals(listOf("codex"), sessions.commands)
    }

    // claudebar://use

    @Test
    fun `should start new sessions with the login a link names by provider and name`() {
        lines.installed += LoginShell.ZSH
        val codex = codex()
        val sessions = sessions(codex)

        assertEquals(NewSessions.LinkOutcome.USED, sessions.use("codex", "work"))
        assertEquals(true, codex.inUse?.isInUse(codex.accounts[1]))
    }

    @Test
    fun `should hold the login a link names until the shell is set up`() {
        val codex = codex()
        val sessions = sessions(codex)

        assertEquals(NewSessions.LinkOutcome.WAITING_FOR_SETUP, sessions.use("codex", "work"))
    }

    @Test
    fun `should do nothing for a link to an unknown provider or login`() {
        val codex = codex()
        val sessions = sessions(codex)

        assertEquals(NewSessions.LinkOutcome.UNKNOWN, sessions.use("gemini", "work"))
        assertEquals(NewSessions.LinkOutcome.UNKNOWN, sessions.use("codex", "someone"))
        assertEquals(true, codex.inUse?.isInUse(codex.defaultAccount))
    }

    // The alert a notice becomes

    @Test
    fun `should link a switch's alert back to the earlier login and a suggestion's alert on to the suggested one`() {
        val codex = codex()
        val (me, work) = codex.defaultAccount to codex.accounts[1]

        val switched = InUseAlert(InUseNotice.Switched(me, work), codex)
        val suggested = InUseAlert(InUseNotice.WorthSwitching(me, work), codex)

        assertTrue(switched.kind == InUseAlert.Kind.SWITCHED && switched.to == "work")
        assertEquals("claudebar://use?provider=codex&account=default", switched.link)
        assertEquals(InUseAlert.Kind.WORTH_SWITCHING, suggested.kind)
        assertEquals("claudebar://use?provider=codex&account=work", suggested.link)
    }

    @Test
    fun `should list only providers whose new sessions can start with a chosen login`() {
        val gemini = alone("gemini")
        val codex = codex()

        val sessions = sessions(gemini, codex)

        assertEquals(listOf("codex"), sessions.products.map { it.id })
        assertSame(codex, sessions.product("codex"))
        assertNull(sessions.product("gemini"))
    }
}
