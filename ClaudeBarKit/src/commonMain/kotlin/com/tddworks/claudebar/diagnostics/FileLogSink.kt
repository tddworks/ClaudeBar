package com.tddworks.claudebar.diagnostics

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.writeString
import kotlin.time.Clock
import kotlin.time.ExperimentalTime

/**
 * The user's log file: `[2026-10-07T07:11:53.616Z] [INFO] [monitor] message`, one line each.
 * Debug lines stay out. Past [maxBytes] the file becomes `ClaudeBar.old.log` and a new one starts.
 */
@OptIn(ExperimentalTime::class)
class FileLogSink(
    directory: String,
    private val maxBytes: Long = 5L * 1024 * 1024,
    private val nowMillis: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) : LogSink {
    private val file = Path(directory, "ClaudeBar.log")
    private val old = Path(directory, "ClaudeBar.old.log")
    private val lock = SynchronizedObject()

    init {
        runCatching { SystemFileSystem.createDirectories(Path(directory)) }
    }

    override fun write(level: LogLevel, category: String, message: String) {
        if (level == LogLevel.DEBUG) return
        val label = if (level == LogLevel.NOTICE) "INFO" else level.name
        val line = "[${isoTimestamp(nowMillis())}] [$label] [$category] $message\n"
        synchronized(lock) {
            runCatching {
                rotateIfNeeded()
                SystemFileSystem.sink(file, append = true).buffered().use { it.writeString(line) }
            }
        }
    }

    private fun rotateIfNeeded() {
        val size = SystemFileSystem.metadataOrNull(file)?.size ?: return
        if (size <= maxBytes) return
        SystemFileSystem.delete(old, mustExist = false)
        SystemFileSystem.atomicMove(file, old)
    }
}

/** UTC, millisecond precision: `2026-10-07T07:11:53.616Z`. */
internal fun isoTimestamp(epochMillis: Long): String {
    val millis = epochMillis.mod(1000L)
    val seconds = epochMillis.floorDiv(1000L)
    val days = seconds.floorDiv(86_400L)
    val secondOfDay = seconds.mod(86_400L)
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    val z = days + 719_468
    val era = z.floorDiv(146_097L)
    val doe = z - era * 146_097
    val yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    val mp = (5 * doy + 2) / 153
    val day = doy - (153 * mp + 2) / 5 + 1
    val month = if (mp < 10) mp + 3 else mp - 9
    val year = yoe + era * 400 + if (month <= 2) 1 else 0
    fun Long.pad(n: Int) = toString().padStart(n, '0')
    return "${year.pad(4)}-${month.pad(2)}-${day.pad(2)}T${(secondOfDay / 3600).pad(2)}:" +
        "${(secondOfDay % 3600 / 60).pad(2)}:${(secondOfDay % 60).pad(2)}.${millis.pad(3)}Z"
}
