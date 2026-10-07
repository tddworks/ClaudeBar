package com.tddworks.claudebar.diagnostics

import kotlin.concurrent.atomics.AtomicReference
import kotlin.native.ObjCName
import kotlin.concurrent.atomics.ExperimentalAtomicApi

/** How much a line matters. Debug goes to the unified log only; the rest also to the file. */
enum class LogLevel { DEBUG, INFO, NOTICE, WARNING, ERROR }

/** Where log lines go — the unified log, the user's log file, a test's list. */
interface LogSink {
    fun write(level: LogLevel, category: String, message: String)
}

/**
 * One category's logger. Messages are written as given, with no redaction: never log a
 * token, key, cookie or credential (AGENTS.md › Logging).
 */
class CategoryLogger internal constructor(val category: String, private val sinks: () -> List<LogSink>) {
    fun debug(message: String) = write(LogLevel.DEBUG, message)
    fun info(message: String) = write(LogLevel.INFO, message)
    fun notice(message: String) = write(LogLevel.NOTICE, message)
    fun warning(message: String) = write(LogLevel.WARNING, message)
    fun error(message: String) = write(LogLevel.ERROR, message)

    private fun write(level: LogLevel, message: String) = sinks().forEach { it.write(level, category, message) }
}

/** The app's log, by category. Writes to the platform's sinks until [install] replaces them. */
@OptIn(ExperimentalAtomicApi::class)
object AppLog {
    private val installed = AtomicReference<List<LogSink>?>(null)

    private fun sinks(): List<LogSink> =
        installed.load() ?: defaultLogSinks().also { installed.compareAndSet(null, it) }

    /** Replaces where lines go — a test's sink, or the kit's at start. */
    fun install(sinks: List<LogSink>) = installed.store(sinks)

    /** Where the user's log file lives (`~/Library/Logs/ClaudeBar` on macOS). */
    val logsDirectory: String get() = logsDirectoryPath()

    @ObjCName("monitorLogger") val monitor = CategoryLogger("monitor", ::sinks)
    @ObjCName("providersLogger") val providers = CategoryLogger("providers", ::sinks)
    @ObjCName("probesLogger") val probes = CategoryLogger("probes", ::sinks)
    @ObjCName("networkLogger") val network = CategoryLogger("network", ::sinks)
    @ObjCName("credentialsLogger") val credentials = CategoryLogger("credentials", ::sinks)
    @ObjCName("uiLogger") val ui = CategoryLogger("ui", ::sinks)
    @ObjCName("notificationsLogger") val notifications = CategoryLogger("notifications", ::sinks)
    @ObjCName("updatesLogger") val updates = CategoryLogger("updates", ::sinks)
    /** Claude Code session tracking. */
    @ObjCName("hooksLogger") val hooks = CategoryLogger("hooks", ::sinks)
}

internal expect fun defaultLogSinks(): List<LogSink>

internal expect fun logsDirectoryPath(): String
