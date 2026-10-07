package com.tddworks.claudebar.datasources.process

import platform.Foundation.NSFileManager
import platform.Foundation.NSFilePosixPermissions
import platform.Foundation.NSNumber
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

/** The real disk behind added logins: private, new, and gone when deleted. */
class DiskLoginFoldersTest {
    private val root = NSTemporaryDirectory().trimEnd('/') + "/login-folders-" + NSUUID().UUIDString

    @AfterTest
    fun removeRoot() {
        NSFileManager.defaultManager.removeItemAtPath(root, null)
    }

    @Test
    fun `should make a login folder private never over another and gone once deleted`() {
        val folder = "$root/codex/login"

        DiskLoginFolders.create(folder)
        val permissions = (NSFileManager.defaultManager.attributesOfItemAtPath(folder, null)?.get(NSFilePosixPermissions) as? NSNumber)?.intValue

        assertEquals(448, permissions) // 0700
        assertFailsWith<SignInError.FolderExists> { DiskLoginFolders.create(folder) }
        DiskLoginFolders.delete(folder)
        assertFalse(DiskLoginFolders.exists(folder))
    }
}
