package com.tddworks.claudebar.datasources.process

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import platform.darwin.openpty
import platform.posix.winsize

/**
 * Programs in a pseudo-terminal of their own. The program gets the terminal's secondary side
 * as standard input, output and error; ClaudeBar reads and types on the primary side, which
 * never blocks. The secondary side stays open here until [TerminalSession.close], so a
 * program that exits leaves its output readable.
 */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object PosixPseudoTerminals : PseudoTerminals {
    override fun start(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        workingDirectory: String?,
        quality: QualityOfService,
        rows: Int,
        cols: Int,
    ): TerminalSession {
        val (primary, secondary) = memScoped {
            val primary = alloc<IntVar>()
            val secondary = alloc<IntVar>()
            val size = alloc<winsize>().apply {
                ws_row = rows.convert()
                ws_col = cols.convert()
                ws_xpixel = 0u
                ws_ypixel = 0u
            }
            if (openpty(primary.ptr, secondary.ptr, null, null, size.ptr) != 0) {
                throw InteractiveRunner.RunError.LaunchFailed("Could not create terminal session")
            }
            primary.value to secondary.value
        }
        PosixSpawn.closeOnExec(primary)
        PosixSpawn.closeOnExec(secondary)
        PosixSpawn.nonBlocking(primary)
        val pid = try {
            PosixSpawn.spawn(
                executable, arguments, environment, workingDirectory, quality,
                (0..2).associateWith { PosixSpawn.Source.Descriptor(secondary) },
            )
        } catch (failed: Throwable) {
            PosixSpawn.closeQuietly(primary)
            PosixSpawn.closeQuietly(secondary)
            throw failed
        }
        return PosixTerminalSession(pid, primary, secondary)
    }
}

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
private class PosixTerminalSession(private val pid: Int, private val primary: Int, private val secondary: Int) : TerminalSession {
    private val lock = SynchronizedObject()
    private var status: Int? = null
    private var closed = false

    override val isRunning: Boolean
        get() = synchronized(lock) {
            if (status == null) status = PosixSpawn.ended(pid)
            status == null
        }

    override val exitStatus: Int
        get() = synchronized(lock) { status?.let(PosixSpawn::exitCode) ?: -1 }

    override fun read(): ByteArray = if (closed) ByteArray(0) else PosixSpawn.readAvailable(primary) ?: ByteArray(0)

    override fun write(bytes: ByteArray) {
        if (!closed) PosixSpawn.writeAll(primary, bytes)
    }

    override fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
        }
        PosixSpawn.closeQuietly(primary)
        PosixSpawn.closeQuietly(secondary)
        if (isRunning) {
            val ended = PosixSpawn.stop(pid)
            synchronized(lock) { status = ended }
        }
    }
}
