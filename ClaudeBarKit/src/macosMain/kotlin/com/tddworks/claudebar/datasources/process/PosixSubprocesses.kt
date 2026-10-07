package com.tddworks.claudebar.datasources.process

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import platform.posix.O_RDONLY
import platform.posix.O_WRONLY

/**
 * Programs over pipes, read as they write so a full pipe never stalls one (the
 * read-after-wait deadlock), always reaped, terminated when the run is cancelled.
 */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object PosixSubprocesses : Subprocesses {
    override suspend fun run(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>?,
        workingDirectory: String?,
        input: String?,
        quality: QualityOfService?,
        outputLimit: Int,
    ): SubprocessOutput {
        val service = quality ?: currentQualityOfService()
        return withContext(Dispatchers.IO) {
            val (stdinRead, stdinWrite) = PosixSpawn.pipe()
            val (stdoutRead, stdoutWrite) = PosixSpawn.pipe()
            val (stderrRead, stderrWrite) = PosixSpawn.pipe()
            val pid = try {
                PosixSpawn.spawn(
                    executable, arguments, environment ?: PosixSpawn.inheritedEnvironment(), workingDirectory, service,
                    mapOf(
                        0 to PosixSpawn.Source.Descriptor(stdinRead),
                        1 to PosixSpawn.Source.Descriptor(stdoutWrite),
                        2 to PosixSpawn.Source.Descriptor(stderrWrite),
                    ),
                )
            } catch (failed: Throwable) {
                listOf(stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite).forEach(PosixSpawn::closeQuietly)
                throw failed
            }
            listOf(stdinRead, stdoutWrite, stderrWrite).forEach(PosixSpawn::closeQuietly)
            listOf(stdinWrite, stdoutRead, stderrRead).forEach(PosixSpawn::nonBlocking)

            var status: Int? = null
            var stdinOpen = true
            try {
                val pending = (input ?: "").encodeToByteArray()
                var written = 0
                val out = CaptureBuffer()
                val err = CaptureBuffer()
                var outOpen = true
                var errOpen = true
                // An empty input closes standard input at once, so `cat` ends instead of waiting.
                if (pending.isEmpty()) {
                    PosixSpawn.closeQuietly(stdinWrite)
                    stdinOpen = false
                }
                while (outOpen || errOpen || status == null) {
                    var progressed = false
                    if (stdinOpen) {
                        val chunk = pending.copyOfRange(written, minOf(pending.size, written + 65_536))
                        val count = PosixSpawn.writeOnce(stdinWrite, chunk)
                        if (count != 0) progressed = true
                        if (count < 0) written = pending.size else written += count
                        if (written >= pending.size) {
                            PosixSpawn.closeQuietly(stdinWrite)
                            stdinOpen = false
                        }
                    }
                    if (outOpen) {
                        val data = PosixSpawn.readAvailable(stdoutRead)
                        if (data == null) outOpen = false else if (data.isNotEmpty()) { out.append(data); progressed = true }
                    }
                    if (errOpen) {
                        val data = PosixSpawn.readAvailable(stderrRead)
                        if (data == null) errOpen = false else if (data.isNotEmpty()) { err.append(data); progressed = true }
                    }
                    if (out.size > outputLimit || err.size > outputLimit) {
                        throw IllegalStateException("The process's output exceeded the limit of $outputLimit bytes.")
                    }
                    if (status == null && !outOpen && !errOpen) status = PosixSpawn.ended(pid)
                    if (!progressed && (outOpen || errOpen || status == null)) delay(5)
                }
                SubprocessOutput(
                    out.toByteArray().decodeToString(),
                    err.toByteArray().decodeToString(),
                    PosixSpawn.exitCode(status),
                )
            } finally {
                if (stdinOpen) PosixSpawn.closeQuietly(stdinWrite)
                PosixSpawn.closeQuietly(stdoutRead)
                PosixSpawn.closeQuietly(stderrRead)
                if (status == null) withContext(NonCancellable) { PosixSpawn.stop(pid, pollMicros = 20_000u) }
            }
        }
    }

    override fun capture(executable: String, arguments: List<String>): SubprocessOutput? {
        val (stdoutRead, stdoutWrite) = runCatching { PosixSpawn.pipe() }.getOrNull() ?: return null
        val pid = try {
            PosixSpawn.spawn(
                executable, arguments, PosixSpawn.inheritedEnvironment(), null, QualityOfService.DEFAULT,
                mapOf(
                    0 to PosixSpawn.Source.File("/dev/null", O_RDONLY),
                    1 to PosixSpawn.Source.Descriptor(stdoutWrite),
                    2 to PosixSpawn.Source.File("/dev/null", O_WRONLY),
                ),
            )
        } catch (failed: SpawnError) {
            PosixSpawn.closeQuietly(stdoutRead)
            PosixSpawn.closeQuietly(stdoutWrite)
            return null
        }
        PosixSpawn.closeQuietly(stdoutWrite)
        // Drain before waiting: waiting first deadlocks once the child fills the pipe.
        val output = CaptureBuffer()
        while (true) {
            val data = PosixSpawn.readAvailable(stdoutRead) ?: break
            output.append(data)
        }
        PosixSpawn.closeQuietly(stdoutRead)
        val status = PosixSpawn.waitFor(pid)
        return SubprocessOutput(output.toByteArray().decodeToString(), "", PosixSpawn.exitCode(status))
    }
}
