package com.tddworks.claudebar.infrastructure.cli

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.refTo
import kotlinx.cinterop.toKString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import platform.Foundation.NSFileManager
import platform.posix.F_OK
import platform.posix.access
import platform.posix.fclose
import platform.posix.fgets
import platform.posix.getenv
import platform.posix.pclose
import platform.posix.popen
import kotlin.time.Duration

/**
 * macOS implementation of CLIExecutor using popen (POSIX).
 * This is simpler and more portable than NSTask.
 */
@OptIn(ExperimentalForeignApi::class)
class AppleCLIExecutor : CLIExecutor {

    override fun locate(binary: String): String? {
        val home = getenv("HOME")?.toKString() ?: ""
        val paths = listOf(
            "/usr/local/bin/$binary",
            "/usr/bin/$binary",
            "/opt/homebrew/bin/$binary",
            "$home/.local/bin/$binary"
        )

        for (path in paths) {
            if (access(path, F_OK) == 0) {
                return path
            }
        }

        // Try 'which' command
        return try {
            val result = executeCommand("which $binary")
            if (result.exitCode == 0) result.output.trim() else null
        } catch (e: Exception) {
            null
        }
    }

    override suspend fun execute(
        binary: String,
        args: List<String>,
        input: String?,
        timeout: Duration,
        workingDirectory: String?,
        autoResponses: Map<String, String>
    ): CLIResult = withContext(Dispatchers.Default) {
        // If binary doesn't contain a path separator, try to locate it first
        val resolvedBinary = if (!binary.contains("/")) {
            locate(binary) ?: binary
        } else {
            binary
        }

        val command = buildString {
            if (workingDirectory != null) {
                append("cd \"$workingDirectory\" && ")
            }
            // Use 'script' to create pseudo-TTY (needed for Claude CLI)
            append("script -q /dev/null ")
            append(resolvedBinary)
            // Filter out empty args
            args.filter { it.isNotEmpty() }.forEach { arg ->
                append(" \"$arg\"")
            }
            // Only add input redirection if input is non-empty
            if (!input.isNullOrEmpty()) {
                append(" <<< \"$input\"")
            }
            // Redirect stderr to stdout to capture all output
            append(" 2>&1")
        }

        println("[AppleCLIExecutor] Running: $command")
        val result = executeCommand(command)
        println("[AppleCLIExecutor] Exit code: ${result.exitCode}")
        println("[AppleCLIExecutor] Output (${result.output.length} chars): ${result.output.take(500)}")
        result
    }

    private fun executeCommand(command: String): CLIResult {
        val fp = popen(command, "r") ?: return CLIResult("Failed to execute", -1)

        val output = StringBuilder()
        val buffer = ByteArray(4096)

        try {
            while (true) {
                val line = fgets(buffer.refTo(0), buffer.size, fp)
                if (line == null) break
                output.append(line.toKString())
            }
        } finally {
            val exitCode = pclose(fp)
            return CLIResult(output.toString(), exitCode)
        }
    }
}
