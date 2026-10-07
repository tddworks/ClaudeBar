package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Paths
import kotlinx.cinterop.BooleanVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.toKString
import kotlinx.cinterop.value
import platform.Foundation.NSFileManager
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSString
import platform.Foundation.stringByResolvingSymlinksInPath
import platform.Foundation.stringByStandardizingPath
import platform.posix.getenv

/** The real file system: `~` and `${VAR:-default}` expanded from this process, symlinks resolved. */
internal class DiskPaths(
    private val home: String = NSHomeDirectory(),
    private val environment: (String) -> String? = { getenv(it)?.toKString() },
) : PathChecking {
    override fun expanded(path: String): String = Paths.expand(path, home, environment)

    override fun isFolder(path: String): Boolean = memScoped {
        val isDirectory = alloc<BooleanVar>()
        NSFileManager.defaultManager.fileExistsAtPath(canonical(path), isDirectory.ptr) && isDirectory.value
    }

    @Suppress("CAST_NEVER_SUCCEEDS")
    override fun canonical(path: String): String {
        val expanded = expanded(path)
        val absolute = if (expanded.startsWith("/")) expanded else NSFileManager.defaultManager.currentDirectoryPath + "/" + expanded
        return ((absolute as NSString).stringByResolvingSymlinksInPath as NSString).stringByStandardizingPath
    }
}
