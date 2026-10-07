package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The terminal executor: a CLI run in a pseudo-terminal by [InteractiveRunner], its screen
 * captured. For a TUI; a CLI that prints machine-readable output goes through [PipeCLIExecutor].
 */
internal class DefaultCLIExecutor(
    private val host: ProcessHost,
    /** Removed before the CLI starts, so a token like `CLAUDE_CODE_OAUTH_TOKEN` isn't inherited. */
    val environmentExclusions: List<String> = emptyList(),
    /** Set on the CLI last — `CLAUDEBAR_PROBE=1`, so ClaudeBar's own hook skips the session (#222). */
    val environmentAdditions: Map<String, String> = emptyMap(),
    /** When the screen has settled; readable so a fetch can be checked for the rule its screen needs (#317). */
    val completionRule: CLICompletionRule? = null,
    /** Seconds before the input is typed, so it lands on a settled TUI screen. */
    val inputDelay: Double = 0.4,
) : CLIExecutor {
    private val runner = InteractiveRunner(host.terminals, host.locator, host.machine, host.files)

    override fun locate(binary: String): String? = host.locator.which(binary)

    override suspend fun execute(
        binary: String,
        args: List<String>,
        input: String?,
        timeoutSeconds: Double,
        workingDirectory: String?,
        autoResponses: Map<String, String>,
    ): CLIResult {
        val options = InteractiveRunner.Options(
            timeout = timeoutSeconds,
            workingDirectory = workingDirectory,
            arguments = args,
            autoResponses = autoResponses,
            environmentExclusions = environmentExclusions,
            environmentAdditions = environmentAdditions,
            completionRule = completionRule,
            inputDelay = inputDelay,
            qualityOfService = currentQualityOfService(),
        )
        // The run polls for up to its timeout; IO keeps that off the threads other refreshes need.
        return withContext(Dispatchers.IO) {
            try {
                runner.run(binary, input ?: "", options).let { CLIResult(it.output, it.exitCode) }
            } catch (missing: InteractiveRunner.RunError.BinaryNotFound) {
                // The fact every caller reads, so a missing CLI is never just a failed run (#198).
                throw UsageError.CliNotFound(missing.tool)
            }
        }
    }
}

/**
 * Runs a command over plain pipes, without a terminal — for a CLI that prints machine-readable
 * output. Standard output and error are read as one text: many CLIs report a problem on stderr.
 */
internal class PipeCLIExecutor(
    private val host: ProcessHost,
    private val change: ProcessEnvironment = ProcessEnvironment(),
) : CLIExecutor {
    override fun locate(binary: String): String? = host.locator.which(binary)

    override suspend fun execute(
        binary: String,
        args: List<String>,
        input: String?,
        timeoutSeconds: Double,
        workingDirectory: String?,
        autoResponses: Map<String, String>,
    ): CLIResult {
        val path = locate(binary) ?: throw UsageError.CliNotFound(binary)
        val environment = environment(path, change)
        // Losing the race cancels the run, which terminates and reaps the command.
        val output = withTimeoutOrNull((timeoutSeconds * 1000).toLong()) {
            host.subprocesses.run(path, args, environment, workingDirectory, input)
        } ?: throw UsageError.Timeout
        return CLIResult(output.standardOutput + output.standardError, output.exitCode)
    }

    /**
     * The app's environment with a PATH that finds tools outside a login shell — launchd's is
     * minimal, which breaks a script whose shebang is `/usr/bin/env node` — then the changes.
     */
    fun environment(binaryPath: String, change: ProcessEnvironment): Map<String, String> {
        val environment = host.machine.environment.toMutableMap()
        val entries = (environment["PATH"] ?: "/usr/bin:/bin:/usr/sbin:/sbin").split(':').filter { it.isNotEmpty() }.toMutableList()
        val seen = entries.toMutableSet()
        val ownDirectory = binaryPath.substringBeforeLast('/', "").ifEmpty { "/" }
        for (directory in listOf(ownDirectory) + host.locator.commonPaths) {
            if (seen.add(directory)) entries += directory
        }
        environment["PATH"] = entries.joinToString(":")
        change.unset.forEach(environment::remove)
        environment.putAll(change.set)
        return environment
    }
}
