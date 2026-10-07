package com.tddworks.claudebar.providers

import platform.Foundation.NSFileManager
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The real file system as a path setting reads it. */
class DiskPathsTest {
    private val files = NSFileManager.defaultManager
    private val root = NSTemporaryDirectory().trimEnd('/') + "/disk-paths-" + NSUUID().UUIDString
    private val paths = DiskPaths(home = root, environment = { null })

    init {
        files.createDirectoryAtPath("$root/work", withIntermediateDirectories = true, attributes = null, error = null)
    }

    @AfterTest
    fun cleanUp() {
        files.removeItemAtPath(root, null)
    }

    @Test
    fun `should expand a home path against the home it is given`() {
        assertEquals("$root/work", paths.expanded("~/work"))
        assertEquals("$root/work", paths.expanded("\${UNSET:-~/work}"))
    }

    @Test
    fun `should find a folder that exists and none where nothing is`() {
        assertTrue(paths.isFolder("~/work"))
        assertFalse(paths.isFolder("~/missing"))
    }

    @Test
    fun `should treat two spellings of one folder as the same place`() {
        files.createSymbolicLinkAtPath("$root/link", withDestinationPath = "$root/work", error = null)

        assertEquals(paths.canonical("$root/work"), paths.canonical("$root/./work"))
        assertEquals(paths.canonical("$root/work"), paths.canonical("~/link"))
    }
}
