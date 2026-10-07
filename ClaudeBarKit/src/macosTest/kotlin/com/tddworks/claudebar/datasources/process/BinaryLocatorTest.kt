package com.tddworks.claudebar.datasources.process

import platform.Foundation.NSFileManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Finding CLIs on this Mac, through its login shell and its install folders. */
class BinaryLocatorTest {
    private val locator = MacProcesses.host.locator

    @Test
    fun `should find a system CLI such as ls`() {
        val path = locator.which("ls")

        assertNotNull(path)
        assertTrue(path.endsWith("/ls"))
    }

    @Test
    fun `should find nothing for a CLI that isn't installed`() {
        assertNull(locator.which("unknown-binary-xyz-123"))
    }

    @Test
    fun `should find a system CLI when a data source looks for it`() {
        assertNotNull(locator.locate("ls"))
    }

    @Test
    fun `should find Homebrew's CLI in Homebrew's folder when the app's PATH lacks it`() {
        val path = locator.findInCommonPaths("brew")

        val files = NSFileManager.defaultManager
        if (files.isExecutableFileAtPath("/opt/homebrew/bin/brew")) {
            assertEquals("/opt/homebrew/bin/brew", path)
        } else if (files.isExecutableFileAtPath("/usr/local/bin/brew")) {
            assertEquals("/usr/local/bin/brew", path)
        }
    }

    @Test
    fun `should find nothing in the common folders for a CLI that isn't installed`() {
        assertNull(locator.findInCommonPaths("unknown-binary-xyz-123-fallback"))
    }

    @Test
    fun `should look in Bun's global folder for CLIs installed with Bun`() {
        assertTrue("${MacMachine.homeDirectory}/.bun/bin" in locator.commonPaths)
    }

    @Test
    fun `should find a system CLI whichever way it is looked up`() {
        val path = locator.which("ls")

        assertNotNull(path)
        assertTrue(path.endsWith("/ls"))
    }
}
