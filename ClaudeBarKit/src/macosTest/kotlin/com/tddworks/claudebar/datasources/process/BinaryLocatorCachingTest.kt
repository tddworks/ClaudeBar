package com.tddworks.claudebar.datasources.process

import platform.Foundation.NSFileManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The caching wired onto the locator every provider asks each refresh. A locator of its own,
 * so another suite forgetting the shared one can't disturb the measurements.
 */
class BinaryLocatorCachingTest {
    private val locator = BinaryLocator(MacMachine, MacFiles, PosixSubprocesses)

    @Test
    fun `should find a CLI at the same runnable path every time it is looked up`() {
        val first = locator.which("sh")
        val second = locator.which("sh")

        assertEquals(first, second)
        if (first != null) assertTrue(NSFileManager.defaultManager.isExecutableFileAtPath(first))
    }

    @Test
    fun `should keep finding nothing for a CLI that isn't installed`() {
        val name = "claudebar-definitely-not-a-real-binary"

        assertNull(locator.which(name))
        assertNull(locator.which(name))
    }

    @Test
    fun `should still find a CLI at the same path after the remembered paths are forgotten`() {
        val before = locator.which("sh")

        locator.invalidateCaches()

        assertEquals(before, locator.which("sh"))
    }

    @Test
    fun `should use a runnable full path as it is`() {
        assertEquals("/bin/echo", locator.which("/bin/echo"))
    }

    @Test
    fun `should find nothing at a full path that isn't runnable or isn't there`() {
        assertNull(locator.which("/etc/hosts"))
        assertNull(locator.which("/bin/claudebar-not-here"))
    }

    @Test
    fun `should know the shell's search path the same every time`() {
        val first = locator.shellPath()
        val second = locator.shellPath()

        assertTrue(first.isNotEmpty())
        assertEquals(first, second)
    }

    @Test
    fun `should start the login shell only once to learn its search path`() {
        locator.invalidateCaches()

        val coldStart = monotonicSeconds()
        locator.shellPath()
        val cold = monotonicSeconds() - coldStart

        val warmStart = monotonicSeconds()
        repeat(50) { locator.shellPath() }
        val warm = monotonicSeconds() - warmStart

        // A loose bound: "no subprocess", not a latency budget.
        assertTrue(warm < maxOf(cold, 0.001), "cold ${cold}s, warm ${warm}s")
    }
}
