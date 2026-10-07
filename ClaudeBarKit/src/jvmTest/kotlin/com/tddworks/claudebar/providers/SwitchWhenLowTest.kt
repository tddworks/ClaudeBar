package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** *Switch when low* — the opt-in policy that moves new sessions off a login running out, to the ticked login with the most left. */
class SwitchWhenLowTest {
    private val fixture = InUseFixture.twoLogins()
    private val stub = fixture.stub
    private val codex = fixture.codex
    private val work = fixture.work

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    @Test
    fun `should switch nowhere until the person turns it on`() {
        val inUse = codex.inUse!!
        InUseFixture.usage(stub, codex, me = 95, work = 10)

        assertFalse(inUse.switchWhenLow.isOn)
        assertNull(inUse.switchWhenLow.next(inUse.login, inUse.logins))
    }

    @Test
    fun `should switch to the ticked login with the most left when the login in use falls below the threshold`() {
        val inUse = codex.inUse!!
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.below = 10
        InUseFixture.usage(stub, codex, me = 95, work = 10)

        assertSame(work, inUse.switchWhenLow.next(inUse.login, inUse.logins))
    }

    @Test
    fun `should not switch when the login in use is above the threshold`() {
        val inUse = codex.inUse!!
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.below = 5
        InUseFixture.usage(stub, codex, me = 90, work = 10)

        assertNull(inUse.switchWhenLow.next(inUse.login, inUse.logins))
    }

    @Test
    fun `should never switch to a login the person unticked`() {
        val inUse = codex.inUse!!
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.setMayPick(false, work)
        InUseFixture.usage(stub, codex, me = 95, work = 10)

        assertFalse(inUse.switchWhenLow.mayPick(work))
        assertNull(inUse.switchWhenLow.next(inUse.login, inUse.logins))
    }

    @Test
    fun `should remember whether it is on, its threshold and the unticked logins across a relaunch`() {
        val policy = codex.inUse!!.switchWhenLow
        policy.isOn = true
        policy.below = 20
        policy.setMayPick(false, work)

        val again = stub.makeProvider("codex", stub.settings.accounts("codex")).inUse!!

        assertTrue(again.switchWhenLow.isOn)
        assertEquals(20, again.switchWhenLow.below)
        assertFalse(again.switchWhenLow.mayPick(again.logins[1]))
        assertTrue(again.switchWhenLow.mayPick(again.login))
    }
}
