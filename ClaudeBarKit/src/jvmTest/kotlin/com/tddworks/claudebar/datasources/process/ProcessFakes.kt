package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.LoginFolders
import java.io.File
import java.util.Collections

// Hand-written stand-ins for the process ports: they answer as told and remember what they were asked.

internal class FakeMachine(
    override val environment: Map<String, String> = emptyMap(),
    override val homeDirectory: String = "/Users/me",
    override val applicationSupportDirectory: String = "/Users/me/Library/Application Support",
    override val architecture: BinaryArchitecture = BinaryArchitecture.ARM64,
) : Machine

/** Files in memory: what exists, what runs, what each holds. */
internal class FakeFiles : MachineFiles {
    private val contents = mutableMapOf<String, ByteArray>()
    private val executables = mutableSetOf<String>()
    private val folders = mutableSetOf<String>()

    /** Puts a file at [path], its folders made, runnable unless said otherwise. */
    fun install(path: String, bytes: ByteArray, executable: Boolean = true): String {
        contents[path] = bytes
        if (executable) executables += path
        makeDirectories(path.substringBeforeLast('/'))
        return path
    }

    override fun isExecutable(path: String) = path in executables
    override fun exists(path: String) = path in contents || path in folders
    override fun list(folder: String): List<String>? = if (folder !in folders) null else
        (contents.keys + folders).filter { it.substringBeforeLast('/') == folder && it != folder }.map { it.substringAfterLast('/') }.distinct()
    override fun header(path: String, bytes: Int): ByteArray? = contents[path]?.let { it.copyOf(minOf(bytes, it.size)) }
    override fun makeDirectories(path: String) {
        var folder = path
        while (folder.isNotEmpty()) {
            folders += folder
            folder = folder.substringBeforeLast('/', "")
        }
    }
}

/** The JVM's view of the real disk, for a test that reads a file macOS ships. */
internal object DiskFiles : MachineFiles {
    override fun isExecutable(path: String) = File(path).canExecute()
    override fun exists(path: String) = File(path).exists()
    override fun list(folder: String): List<String>? = File(folder).list()?.toList()
    override fun header(path: String, bytes: Int): ByteArray? =
        runCatching { File(path).inputStream().use { it.readNBytes(bytes) } }.getOrNull()
    override fun makeDirectories(path: String) {
        File(path).mkdirs()
    }
}

/** Programs that never start: [capture] answers from a table, [run] says it was not expected. */
internal class FakeSubprocesses(private val captures: Map<List<String>, SubprocessOutput?> = emptyMap()) : Subprocesses {
    val captured: MutableList<List<String>> = Collections.synchronizedList(mutableListOf())

    override suspend fun run(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>?,
        workingDirectory: String?,
        input: String?,
        quality: QualityOfService?,
        outputLimit: Int,
    ): SubprocessOutput = error("no program runs over pipes in this test")

    override fun capture(executable: String, arguments: List<String>): SubprocessOutput? {
        val call = listOf(executable) + arguments
        captured += call
        return captures[call]
    }
}

internal object NoTerminals : PseudoTerminals {
    override fun start(
        executable: String,
        arguments: List<String>,
        environment: Map<String, String>,
        workingDirectory: String?,
        quality: QualityOfService,
        rows: Int,
        cols: Int,
    ): TerminalSession = error("no terminal opens in this test")
}

/** A host whose CLIs are never found: no login shell answers and no file exists. */
internal fun fakeHost(machine: Machine = FakeMachine(), files: MachineFiles = FakeFiles()) =
    ProcessHost(machine, files, FakeSubprocesses(), NoTerminals, RunningProcesses { emptyList() })

/** One `execute` as the executor saw it. */
internal data class Execution(
    val binary: String,
    val args: List<String>,
    val input: String?,
    val timeoutSeconds: Double,
    val workingDirectory: String?,
    val autoResponses: Map<String, String>,
)

/** An executor that finds the CLI at [path] (none when null) and answers each run with [answer]. */
internal class FakeCLIExecutor(
    private val path: String? = "/usr/local/bin/acme",
    private val answer: (Execution) -> CLIResult = { CLIResult("") },
) : CLIExecutor {
    val executions: MutableList<Execution> = Collections.synchronizedList(mutableListOf())

    override fun locate(binary: String): String? = path

    override suspend fun execute(
        binary: String,
        args: List<String>,
        input: String?,
        timeoutSeconds: Double,
        workingDirectory: String?,
        autoResponses: Map<String, String>,
    ): CLIResult {
        val execution = Execution(binary, args, input, timeoutSeconds, workingDirectory, autoResponses)
        executions += execution
        return answer(execution)
    }
}

/** Login folders in memory: what exists after adding, signing in and removing. */
internal class InMemoryLoginFolders(existing: List<String> = emptyList()) : LoginFolders {
    private val folders = Collections.synchronizedSet(existing.toMutableSet())

    val all: Set<String> get() = synchronized(folders) { folders.toSet() }

    override fun exists(folder: String) = folder in folders

    override fun create(folder: String) {
        if (!folders.add(folder)) throw SignInError.FolderExists
    }

    override fun delete(folder: String) {
        folders.remove(folder)
    }
}
