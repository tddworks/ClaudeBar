package com.tddworks.claudebar.activity

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** In a temporary home, never the person's own. */
class PortDiscoveryTest {
    @TempDir
    lateinit var home: File

    private val discovery get() = PortDiscovery.inHome(home.path)

    @Test
    fun `should leave ClaudeBar's port in claudebar-hook-port under the hidden claude folder`() {
        val path = discovery.portFilePath
        assertTrue(path.contains(".claude"))
        assertTrue(path.endsWith("claudebar-hook-port"))
    }

    @Test
    fun `should read back the port ClaudeBar left`() {
        discovery.writePort(19847)

        assertEquals(19847, discovery.readPort())
    }

    @Test
    fun `should find no port once ClaudeBar removes its port file`() {
        discovery.writePort(12345)
        discovery.removePortFile()

        assertNull(discovery.readPort())
    }

    @Test
    fun `should find no port when ClaudeBar left no port file`() {
        discovery.removePortFile()

        assertNull(discovery.readPort())
    }

    @Test
    fun `should read back the port ClaudeBar left on a later write`() {
        // The .claude folder is created when it doesn't exist.
        discovery.writePort(9999)

        assertEquals(9999, discovery.readPort())
    }
}
