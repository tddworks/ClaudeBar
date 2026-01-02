package com.tddworks.claudebar.infrastructure.platform

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSFileManager
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.stringWithContentsOfFile

@OptIn(ExperimentalForeignApi::class)
actual object FileSystem {
    actual fun homeDirectory(): String {
        return NSHomeDirectory()
    }

    actual fun fileExists(path: String): Boolean {
        return NSFileManager.defaultManager.fileExistsAtPath(path)
    }

    actual fun readFile(path: String): String? {
        return try {
            NSString.stringWithContentsOfFile(path, NSUTF8StringEncoding, null)
        } catch (e: Exception) {
            null
        }
    }
}
