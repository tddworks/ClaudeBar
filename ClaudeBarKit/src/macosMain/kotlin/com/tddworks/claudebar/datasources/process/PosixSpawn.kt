package com.tddworks.claudebar.datasources.process

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.COpaquePointerVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.UIntVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.allocArrayOf
import kotlinx.cinterop.get
import kotlinx.cinterop.convert
import kotlinx.cinterop.cstr
import kotlinx.cinterop.invoke
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.toKString
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import platform.Foundation.NSProcessInfo
import platform.posix.EAGAIN
import platform.posix.EINTR
import platform.posix.FD_CLOEXEC
import platform.posix.F_GETFL
import platform.posix.F_SETFD
import platform.posix.F_SETFL
import platform.posix.F_SETNOSIGPIPE
import platform.posix.O_NONBLOCK
import platform.posix.RTLD_DEFAULT
import platform.posix.SIGKILL
import platform.posix.SIGTERM
import platform.posix.WNOHANG
import platform.posix.close
import platform.posix.dlsym
import platform.posix.errno
import platform.posix.fcntl
import platform.posix.kill
import platform.posix.pipe
import platform.posix.read
import platform.posix.strerror
import platform.posix.usleep
import platform.posix.waitpid
import platform.posix.write

/** A program that could not be started, with the system's reason. */
internal class SpawnError(val code: Int, message: String) : Exception(message)

/**
 * `posix_spawn` for the process adapters. The platform libraries don't bind `spawn.h`, so its
 * functions are looked up with `dlsym`. Every child starts with default signal handling, an
 * empty signal mask and only the descriptors it is given (`POSIX_SPAWN_CLOEXEC_DEFAULT`), and
 * at the fetch's quality of service (#204) — what `Foundation.Process` gave it.
 */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object PosixSpawn {
    /** Where a child's descriptor comes from: one of ours, or a file opened for it. */
    sealed class Source {
        data class Descriptor(val fd: Int) : Source()
        data class File(val path: String, val flags: Int) : Source()
    }

    private const val SETSIGDEF = 0x04
    private const val SETSIGMASK = 0x08
    private const val CLOEXEC_DEFAULT = 0x4000

    private val spawn = function<(CPointer<IntVar>?, CPointer<ByteVar>?, COpaquePointer?, COpaquePointer?, CPointer<CPointerVar<ByteVar>>?, CPointer<CPointerVar<ByteVar>>?) -> Int>("posix_spawn")
    private val actionsInit = function<(COpaquePointer?) -> Int>("posix_spawn_file_actions_init")
    private val actionsDestroy = function<(COpaquePointer?) -> Int>("posix_spawn_file_actions_destroy")
    private val addDup2 = function<(COpaquePointer?, Int, Int) -> Int>("posix_spawn_file_actions_adddup2")
    private val addOpen = function<(COpaquePointer?, Int, CPointer<ByteVar>?, Int, UShort) -> Int>("posix_spawn_file_actions_addopen")
    private val addChdir = function<(COpaquePointer?, CPointer<ByteVar>?) -> Int>("posix_spawn_file_actions_addchdir_np")
    private val attrInit = function<(COpaquePointer?) -> Int>("posix_spawnattr_init")
    private val attrDestroy = function<(COpaquePointer?) -> Int>("posix_spawnattr_destroy")
    private val setFlags = function<(COpaquePointer?, Short) -> Int>("posix_spawnattr_setflags")
    private val setSigMask = function<(COpaquePointer?, CPointer<UIntVar>?) -> Int>("posix_spawnattr_setsigmask")
    private val setSigDefault = function<(COpaquePointer?, CPointer<UIntVar>?) -> Int>("posix_spawnattr_setsigdefault")
    private val setQos = function<(COpaquePointer?, UInt) -> Int>("posix_spawnattr_set_qos_class_np")

    private fun <T : Function<*>> function(name: String): CPointer<CFunction<T>> =
        requireNotNull(dlsym(RTLD_DEFAULT, name)) { "$name is not available" }.reinterpret()

    /** The app's own environment, which a child inherits when it is given none. */
    fun inheritedEnvironment(): Map<String, String> =
        NSProcessInfo.processInfo.environment.entries.associate { (key, value) -> key.toString() to value.toString() }

    /** Starts [executable] (a full path) and returns its pid; throws [SpawnError]. */
    fun spawn(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        workingDirectory: String?,
        quality: QualityOfService,
        streams: Map<Int, Source>,
    ): Int = memScoped {
        val actions = alloc<COpaquePointerVar>()
        val attributes = alloc<COpaquePointerVar>()
        actionsInit(actions.ptr)
        attrInit(attributes.ptr)
        try {
            for ((target, source) in streams) {
                when (source) {
                    is Source.Descriptor -> addDup2(actions.ptr, source.fd, target)
                    is Source.File -> addOpen(actions.ptr, target, source.path.cstr.ptr, source.flags, 0u)
                }
            }
            if (workingDirectory != null) addChdir(actions.ptr, workingDirectory.cstr.ptr)
            setFlags(attributes.ptr, (SETSIGDEF or SETSIGMASK or CLOEXEC_DEFAULT).toShort())
            val emptyMask = alloc<UIntVar>().apply { value = 0u }
            setSigMask(attributes.ptr, emptyMask.ptr)
            // Every catchable signal back to its default: SIGKILL (9) and SIGSTOP (17) can't be.
            val defaults = alloc<UIntVar>().apply { value = 0xFFFFFFFFu and (1u shl 8).inv() and (1u shl 16).inv() }
            setSigDefault(attributes.ptr, defaults.ptr)
            qosClass(quality)?.let { setQos(attributes.ptr, it) }

            val argv = allocArrayOf((listOf(executable) + arguments).map { it.cstr.ptr } + listOf(null))
            val envp = allocArrayOf(environment.map { (key, value) -> "$key=$value".cstr.ptr } + listOf(null))
            val pid = alloc<IntVar>()
            val result = spawn(pid.ptr, executable.cstr.ptr, actions.ptr, attributes.ptr, argv, envp)
            if (result != 0) throw SpawnError(result, "Failed to start $executable: ${strerror(result)?.toKString()}")
            pid.value
        } finally {
            actionsDestroy(actions.ptr)
            attrDestroy(attributes.ptr)
        }
    }

    /** Darwin's QoS classes; `DEFAULT` leaves the child the class it inherits, as Foundation does. */
    private fun qosClass(quality: QualityOfService): UInt? = when (quality) {
        QualityOfService.USER_INTERACTIVE -> 0x21u
        QualityOfService.USER_INITIATED -> 0x19u
        QualityOfService.DEFAULT -> null
        QualityOfService.UTILITY -> 0x11u
        QualityOfService.BACKGROUND -> 0x09u
    }

    /** A pipe: (read end, write end), both closed on exec and the write end never raising SIGPIPE. */
    fun pipe(): Pair<Int, Int> = memScoped {
        val fds = allocArray<IntVar>(2)
        if (pipe(fds) != 0) throw SpawnError(errno, "Could not create a pipe: ${strerror(errno)?.toKString()}")
        val pair = fds[0] to fds[1]
        closeOnExec(pair.first)
        closeOnExec(pair.second)
        fcntl(pair.second, F_SETNOSIGPIPE, 1)
        pair
    }

    fun closeOnExec(fd: Int) {
        fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    fun nonBlocking(fd: Int) {
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) or O_NONBLOCK)
    }

    /** The raw wait status once [pid] has ended, without waiting; null while it runs. */
    fun ended(pid: Int): Int? = memScoped {
        val status = alloc<IntVar>()
        val result = waitpid(pid, status.ptr, WNOHANG)
        when {
            result == pid -> status.value
            result < 0 && errno != EINTR -> 0
            else -> null
        }
    }

    /** Waits for [pid] to end and returns its raw wait status. */
    fun waitFor(pid: Int): Int = memScoped {
        val status = alloc<IntVar>()
        var result: Int
        do {
            result = waitpid(pid, status.ptr, 0)
        } while (result < 0 && errno == EINTR)
        if (result == pid) status.value else 0
    }

    /** Foundation's convention: the exit code, or the number of the signal that ended it. */
    fun exitCode(status: Int): Int = if (status and 0x7F == 0) (status shr 8) and 0xFF else status and 0x7F

    /**
     * Stops [pid] the way the Swift runners did — SIGTERM, up to two seconds, then SIGKILL —
     * and reaps it. Returns its raw wait status.
     */
    fun stop(pid: Int, pollMicros: UInt = 100_000u): Int {
        ended(pid)?.let { return it }
        kill(pid, SIGTERM)
        val deadline = monotonicSeconds() + 2.0
        while (monotonicSeconds() < deadline) {
            ended(pid)?.let { return it }
            usleep(pollMicros)
        }
        kill(pid, SIGKILL)
        return waitFor(pid)
    }

    /** Everything readable on a non-blocking [fd] now; null at end of file. */
    fun readAvailable(fd: Int): ByteArray? {
        val chunk = ByteArray(8192)
        var result = ByteArray(0)
        while (true) {
            val count = chunk.usePinned { read(fd, it.addressOf(0), chunk.size.convert()) }.toInt()
            when {
                count > 0 -> result += chunk.copyOf(count)
                count == 0 -> return if (result.isEmpty()) null else result
                errno == EINTR -> continue
                errno == EAGAIN -> return result
                else -> return if (result.isEmpty()) null else result
            }
        }
    }

    /** One write: the bytes taken, 0 when the buffer is full, -1 when the reader is gone. */
    fun writeOnce(fd: Int, bytes: ByteArray): Int {
        if (bytes.isEmpty()) return 0
        val count = bytes.usePinned { write(fd, it.addressOf(0), bytes.size.convert()) }.toInt()
        return when {
            count >= 0 -> count
            errno == EAGAIN || errno == EINTR -> 0
            else -> -1
        }
    }

    /** Writes all of [bytes], waiting out a full buffer; false when the reader is gone. */
    fun writeAll(fd: Int, bytes: ByteArray): Boolean {
        var offset = 0
        while (offset < bytes.size) {
            val count = bytes.usePinned { write(fd, it.addressOf(offset), (bytes.size - offset).convert()) }.toInt()
            when {
                count > 0 -> offset += count
                errno == EAGAIN || errno == EINTR -> usleep(1_000u)
                else -> return false
            }
        }
        return true
    }

    fun closeQuietly(fd: Int) {
        if (fd >= 0) close(fd)
    }
}
