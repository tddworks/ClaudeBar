package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.LoginFolders
import com.tddworks.claudebar.datasources.SignInProcess
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.ULongVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.convert
import kotlinx.cinterop.get
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.sizeOf
import kotlinx.cinterop.toKString
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSFilePosixPermissions
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSNumber
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUserDomainMask
import platform.darwin.sysctlbyname
import platform.osx.proc_listallpids
import platform.osx.proc_pidpath
import platform.posix.O_RDONLY
import platform.posix.O_WRONLY
import platform.posix.close
import platform.posix.open
import platform.posix.read

/** This Mac's process facilities, wired once so every worker shares one locator and its caches. */
internal object MacProcesses {
    val host = ProcessHost(MacMachine, MacFiles, PosixSubprocesses, PosixPseudoTerminals, SystemRunningProcesses)

    /** JSON-RPC pipes to CLIs, found through the shared locator. */
    val transports = RPCTransportFactory { executable, arguments, environment, workingDirectory ->
        ProcessRPCTransport(host.locator, executable, arguments, environment, workingDirectory)
    }
}

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object MacMachine : Machine {
    override val environment: Map<String, String> get() = PosixSpawn.inheritedEnvironment()

    override val homeDirectory: String get() = NSHomeDirectory()

    override val applicationSupportDirectory: String
        get() = (NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, true).firstOrNull() as? String)
            ?: NSTemporaryDirectory()

    /** `hw.machine`: the kernel's architecture, not this process's — what the children it spawns run as. */
    override val architecture: BinaryArchitecture by lazy {
        val machine = memScoped {
            val size = alloc<ULongVar>()
            if (sysctlbyname("hw.machine", null, size.ptr, null, 0u) != 0 || size.value == 0uL) return@memScoped null
            val value = allocArray<ByteVar>(size.value.toInt())
            if (sysctlbyname("hw.machine", value, size.ptr, null, 0u) != 0) null else value.toKString()
        }
        if (machine?.startsWith("x86_64") == true) BinaryArchitecture.X86_64 else BinaryArchitecture.ARM64
    }
}

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object MacFiles : MachineFiles {
    private val files get() = NSFileManager.defaultManager

    override fun isExecutable(path: String): Boolean = files.isExecutableFileAtPath(path)

    override fun exists(path: String): Boolean = files.fileExistsAtPath(path)

    override fun list(folder: String): List<String>? =
        files.contentsOfDirectoryAtPath(folder, null)?.map { it.toString() }

    override fun header(path: String, bytes: Int): ByteArray? {
        val fd = open(path, O_RDONLY)
        if (fd < 0) return null
        try {
            val buffer = ByteArray(bytes)
            val count = buffer.usePinned { read(fd, it.addressOf(0), bytes.convert()) }.toInt()
            return if (count < 0) null else buffer.copyOf(count)
        } finally {
            close(fd)
        }
    }

    override fun makeDirectories(path: String) {
        files.createDirectoryAtPath(path, withIntermediateDirectories = true, attributes = null, error = null)
    }
}

/** The executable paths of the processes running now, from the kernel's process table. */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
internal object SystemRunningProcesses : RunningProcesses {
    override fun executablePaths(): List<String> = memScoped {
        val capacity = proc_listallpids(null, 0) + 64
        if (capacity <= 64) return@memScoped emptyList()
        val pids = allocArray<IntVar>(capacity)
        val count = proc_listallpids(pids, capacity * sizeOf<IntVar>().toInt())
        val buffer = allocArray<ByteVar>(PATH_BUFFER)
        val paths = mutableListOf<String>()
        for (index in 0 until maxOf(0, minOf(count, capacity))) {
            val pid = pids[index]
            if (pid > 0 && proc_pidpath(pid, buffer, PATH_BUFFER.convert()) > 0) paths += buffer.toKString()
        }
        paths
    }

    /** `PROC_PIDPATHINFO_MAXSIZE`: four times MAXPATHLEN. */
    private const val PATH_BUFFER = 4 * 1024
}

/**
 * A login as a child process, its output never read or logged — a login's diagnostics can
 * carry a token. Stopped when the time is up ([SignInError.TimedOut]) or the caller is cancelled.
 */
internal object PosixSignInProcess : SignInProcess {
    override suspend fun run(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        directory: String,
        timeoutSeconds: Double,
    ): Int = withContext(Dispatchers.IO) {
        val pid = PosixSpawn.spawn(
            executable, arguments, environment, directory, QualityOfService.DEFAULT,
            mapOf(
                0 to PosixSpawn.Source.File("/dev/null", O_RDONLY),
                1 to PosixSpawn.Source.File("/dev/null", O_WRONLY),
                2 to PosixSpawn.Source.File("/dev/null", O_WRONLY),
            ),
        )
        var status: Int? = null
        try {
            val deadline = monotonicSeconds() + timeoutSeconds
            while (true) {
                status = PosixSpawn.ended(pid)
                if (status != null) break
                currentCoroutineContext().ensureActive()
                if (monotonicSeconds() >= deadline) throw SignInError.TimedOut
                delay(200)
            }
            PosixSpawn.exitCode(status)
        } finally {
            if (status == null) withContext(NonCancellable) { PosixSpawn.stop(pid) }
        }
    }
}

/** The real disk behind added logins: new folders only, private (0700), gone when deleted. */
internal object DiskLoginFolders : LoginFolders {
    private val files get() = NSFileManager.defaultManager

    override fun exists(folder: String): Boolean = files.fileExistsAtPath(folder)

    override fun create(folder: String) {
        if (files.fileExistsAtPath(folder)) throw SignInError.FolderExists
        val private = mapOf<Any?, Any?>(NSFilePosixPermissions to NSNumber(int = 448))
        val parent = folder.trimEnd('/').substringBeforeLast('/', "").ifEmpty { "/" }
        check(files.createDirectoryAtPath(parent, withIntermediateDirectories = true, attributes = private, error = null)) {
            "Could not make $parent"
        }
        check(files.createDirectoryAtPath(folder, withIntermediateDirectories = false, attributes = private, error = null)) {
            "Could not make $folder"
        }
    }

    override fun delete(folder: String) {
        files.removeItemAtPath(folder, null)
    }
}
