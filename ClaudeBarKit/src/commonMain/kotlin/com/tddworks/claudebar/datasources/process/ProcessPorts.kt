package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.RPCTransport
import com.tddworks.claudebar.datasources.WorkingDirectory
import kotlin.time.DurationUnit
import kotlin.time.TimeSource

// The ports the process workers stand on: this Mac, its files, and the two ways a program
// is started — over pipes, or in a pseudo-terminal. Adapters live in macosMain; tests fake them.

/** The Mac the app runs on. */
internal interface Machine {
    /** The app's own environment — launchd's when it starts from Finder or at login. */
    val environment: Map<String, String>
    val homeDirectory: String
    /** `~/Library/Application Support`, or a temporary folder when there is none. */
    val applicationSupportDirectory: String
    /** What this Mac runs natively — arm64 on Apple Silicon even while ClaudeBar runs translated. */
    val architecture: BinaryArchitecture
}

/** The files a CLI lookup and a script check look at. */
internal interface MachineFiles {
    /** As `access(X_OK)` answers: a folder with its execute bit set counts. */
    fun isExecutable(path: String): Boolean
    fun exists(path: String): Boolean
    /** The names in a folder; null when it can't be listed. */
    fun list(folder: String): List<String>?
    /** Up to [bytes] bytes from a file's start; null when it can't be read. */
    fun header(path: String, bytes: Int): ByteArray?
    /** Makes a folder and its parents; nothing when it is there. */
    fun makeDirectories(path: String)
}

/** What a program printed over pipes, and how it ended — its exit code, or the signal that killed it. */
internal data class SubprocessOutput(val standardOutput: String, val standardError: String, val exitCode: Int) {
    val isSuccess: Boolean get() = exitCode == 0
}

/** Programs run over plain pipes, without a terminal. */
internal interface Subprocesses {
    /**
     * Runs a program to its end, reading both pipes as it goes so a full pipe never stalls
     * it. A non-zero exit is returned, not thrown; a cancelled run terminates and reaps the
     * program. [environment] null inherits the app's; [quality] null is the fetch's own
     * ([currentQualityOfService]). More than [outputLimit] bytes on either pipe throws.
     */
    suspend fun run(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>? = null,
        workingDirectory: String? = null,
        input: String? = null,
        quality: QualityOfService? = null,
        outputLimit: Int = DEFAULT_OUTPUT_LIMIT,
    ): SubprocessOutput

    /**
     * Runs a short program on the caller's thread — a login shell's `which` — and returns what
     * it printed on standard output, or null when it couldn't start. Standard error is dropped.
     */
    fun capture(executable: String, arguments: List<String>): SubprocessOutput?

    companion object {
        /** 1 MiB per pipe. */
        const val DEFAULT_OUTPUT_LIMIT = 1 shl 20
    }
}

/** Programs run in a pseudo-terminal, so a TUI draws as it would for a person. */
internal interface PseudoTerminals {
    /**
     * Starts [executable] with a [rows]×[cols] terminal as its standard input, output and
     * error. Throws [InteractiveRunner.RunError.LaunchFailed] when no terminal can be opened,
     * or the launch's own error when the program can't start.
     */
    fun start(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        workingDirectory: String?,
        quality: QualityOfService,
        rows: Int,
        cols: Int,
    ): TerminalSession
}

/** One program running in a pseudo-terminal. */
internal interface TerminalSession {
    val isRunning: Boolean
    /** How it ended — its exit code, or the signal that killed it; meaningful once it has. */
    val exitStatus: Int
    /** Whatever it wrote since the last read; empty when nothing waits. Never blocks. */
    fun read(): ByteArray
    fun write(bytes: ByteArray)
    /** Closes the terminal, then stops the program — SIGTERM, up to 2 s, SIGKILL — and reaps it. */
    fun close()
}

/** The executable paths of the processes running now, read without starting a process. */
internal fun interface RunningProcesses {
    fun executablePaths(): List<String>
}

/** Opens a JSON-RPC pipe to a CLI — `ProcessRPCTransport` on the Mac. */
internal fun interface RPCTransportFactory {
    /** [environment] null inherits the app's. Throws `UsageError.CliNotFound` when the CLI isn't there. */
    fun open(executable: String, arguments: List<String>, environment: Map<String, String>?, workingDirectory: String?): RPCTransport
}

/** This Mac's process facilities, together, as the workers that start processes need them. */
internal class ProcessHost(
    val machine: Machine,
    val files: MachineFiles,
    val subprocesses: Subprocesses,
    val terminals: PseudoTerminals,
    val runningProcesses: RunningProcesses,
) {
    /** One locator per host, so every worker shares its caches. */
    val locator = BinaryLocator(machine, files, subprocesses)

    /** Where a CLI runs: `dedicated` is ClaudeBar's own trusted folder. */
    fun directory(of: WorkingDirectory): String = when (of) {
        WorkingDirectory.DEDICATED -> CLIWorkingDirectory.resolve(machine, files)
    }
}

private val processClockStart = TimeSource.Monotonic.markNow()

/** Seconds on a clock that only moves forward, for timeouts and cache lifetimes. */
internal fun monotonicSeconds(): Double = processClockStart.elapsedNow().toDouble(DurationUnit.SECONDS)

/** Seconds to three places, for a log line. */
internal fun Double.secondsText(): String = ((this * 1000).toLong() / 1000.0).toString()
