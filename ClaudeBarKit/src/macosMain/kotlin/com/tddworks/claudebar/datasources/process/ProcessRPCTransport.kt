package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.RPCTransport
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.delay
import platform.posix.O_WRONLY

/**
 * JSON-RPC over a CLI's standard input and output, a message per line. A write to a CLI
 * that already exited fails as an error (never SIGPIPE); [close] lets the CLI see EOF, then
 * stops and reaps it so it never lingers as a zombie.
 */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal class ProcessRPCTransport(
    locator: BinaryLocator,
    executable: String,
    arguments: List<String>,
    environment: Map<String, String>? = null,
    /** Some CLIs (Codex 0.150+, #267) trust-check the folder they start in, so the caller picks it. */
    workingDirectory: String? = null,
) : RPCTransport {
    private val pid: Int
    private val stdinWrite: Int
    private val stdoutRead: Int
    private val pending = CaptureBuffer()
    private var consumed = 0
    private var ended = false
    private var closed = false

    init {
        val path = locator.which(executable)
        if (path == null) {
            AppLog.probes.error("RPC transport: '$executable' not found in PATH")
            AppLog.probes.debug("Shell PATH: ${locator.shellPath()}")
            throw UsageError.CliNotFound(executable)
        }
        AppLog.probes.debug("RPC transport: Found '$executable' at: $path")
        val variables = (environment ?: PosixSpawn.inheritedEnvironment()).toMutableMap()
        variables["PATH"] = locator.shellPath()
        val (inRead, inWrite) = PosixSpawn.pipe()
        val (outRead, outWrite) = PosixSpawn.pipe()
        pid = try {
            PosixSpawn.spawn(
                path, arguments, variables, workingDirectory, QualityOfService.DEFAULT,
                mapOf(
                    0 to PosixSpawn.Source.Descriptor(inRead),
                    1 to PosixSpawn.Source.Descriptor(outWrite),
                    2 to PosixSpawn.Source.File("/dev/null", O_WRONLY),
                ),
            )
        } catch (failed: Throwable) {
            listOf(inRead, inWrite, outRead, outWrite).forEach(PosixSpawn::closeQuietly)
            AppLog.probes.error("RPC transport: Failed to start '$executable' at $path: ${failed.message}")
            throw UsageError.ExecutionFailed("Failed to start $executable: ${failed.message}")
        }
        PosixSpawn.closeQuietly(inRead)
        PosixSpawn.closeQuietly(outWrite)
        PosixSpawn.nonBlocking(outRead)
        stdinWrite = inWrite
        stdoutRead = outRead
    }

    override fun send(data: ByteArray) {
        if (closed || !PosixSpawn.writeAll(stdinWrite, data + '\n'.code.toByte())) {
            AppLog.probes.error("RPC transport: Failed to write to stdin")
            throw UsageError.ExecutionFailed("RPC transport write failed: the process closed its input")
        }
    }

    override suspend fun receive(): ByteArray {
        while (true) {
            nextLine()?.let { return it }
            if (ended || closed) {
                remainder()?.let { return it }
                throw UsageError.ExecutionFailed("Process closed unexpectedly")
            }
            val data = PosixSpawn.readAvailable(stdoutRead)
            when {
                data == null -> ended = true
                data.isEmpty() -> delay(5)
                else -> pending.append(data)
            }
        }
    }

    /** The next non-empty line received, without its line break. */
    private fun nextLine(): ByteArray? {
        val bytes = pending.toByteArray()
        while (true) {
            val newline = (consumed until bytes.size).firstOrNull { bytes[it] == '\n'.code.toByte() } ?: return null
            var line = bytes.copyOfRange(consumed, newline)
            consumed = newline + 1
            if (line.isNotEmpty() && line.last() == '\r'.code.toByte()) line = line.copyOf(line.size - 1)
            if (line.isNotEmpty()) return line
        }
    }

    /** What is left after the last line break, once the output has ended. */
    private fun remainder(): ByteArray? {
        val bytes = pending.toByteArray()
        if (consumed >= bytes.size) return null
        val line = bytes.copyOfRange(consumed, bytes.size)
        consumed = bytes.size
        return line.takeIf { it.isNotEmpty() }
    }

    override fun close() {
        if (closed) return
        closed = true
        // Closing stdin is the graceful exit: an app server sees EOF and shuts down on its own.
        PosixSpawn.closeQuietly(stdinWrite)
        PosixSpawn.stop(pid, pollMicros = 50_000u)
        PosixSpawn.closeQuietly(stdoutRead)
    }
}
