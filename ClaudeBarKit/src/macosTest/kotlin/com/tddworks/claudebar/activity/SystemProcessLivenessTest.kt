package com.tddworks.claudebar.activity

import platform.posix.getpid
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Against the real kernel. */
class SystemProcessLivenessTest {
    private val liveness = SystemProcessLiveness()

    @Test
    fun `should find this very process running`() {
        assertTrue(liveness.isRunning(getpid()))
    }

    @Test
    fun `should find a process owned by someone else running`() {
        // launchd is root's; kill answers EPERM, which still means it exists.
        assertTrue(liveness.isRunning(1))
    }

    @Test
    fun `should find no process behind a number no process has`() {
        assertFalse(liveness.isRunning(Int.MAX_VALUE))
    }

    @Test
    fun `should find no process behind zero or a negative number`() {
        assertFalse(liveness.isRunning(0))
        assertFalse(liveness.isRunning(-1))
    }
}
