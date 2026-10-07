package com.tddworks.claudebar.diagnostics

import com.tddworks.claudebar.diagnostics.oslog.claudebar_os_log
import com.tddworks.claudebar.diagnostics.oslog.claudebar_os_log_create
import kotlinx.cinterop.COpaquePointer
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSBundle
import platform.Foundation.NSFileManager
import platform.Foundation.NSLibraryDirectory
import platform.Foundation.NSURL
import platform.Foundation.NSUserDomainMask

/** The unified log (Console.app, `log show --predicate 'subsystem == "…"'`), one os_log per category. */
@OptIn(ExperimentalForeignApi::class)
class UnifiedLogSink(private val subsystem: String) : LogSink {
    private val logs = mutableMapOf<String, COpaquePointer?>()
    private val lock = SynchronizedObject()

    override fun write(level: LogLevel, category: String, message: String) {
        val log = synchronized(lock) { logs.getOrPut(category) { claudebar_os_log_create(subsystem, category) } }
        claudebar_os_log(log, level.osLogType, message)
    }

    // OS_LOG_TYPE_*: Swift's Logger writes warning as error, notice as default.
    private val LogLevel.osLogType: UByte
        get() = when (this) {
            LogLevel.DEBUG -> 0x02u
            LogLevel.INFO -> 0x01u
            LogLevel.NOTICE -> 0x00u
            LogLevel.WARNING, LogLevel.ERROR -> 0x10u
        }
}

internal actual fun defaultLogSinks(): List<LogSink> = listOf(
    UnifiedLogSink(NSBundle.mainBundle.bundleIdentifier ?: "com.tddworks.ClaudeBar"),
    FileLogSink(logsDirectoryPath()),
)

/** `~/Library/Logs/ClaudeBar`, honouring a home moved for a sample-data run. */
internal actual fun logsDirectoryPath(): String {
    val library = NSFileManager.defaultManager.URLsForDirectory(NSLibraryDirectory, NSUserDomainMask)
        .firstOrNull() as? NSURL
    return (library?.path ?: "") + "/Logs/ClaudeBar"
}
