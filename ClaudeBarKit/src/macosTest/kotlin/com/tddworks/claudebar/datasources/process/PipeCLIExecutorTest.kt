package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.ProcessEnvironment
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.TimeSource

/**
 * Commands over plain pipes, end to end — what the Swift app's `SimpleCLIExecutor` did, and what
 * `PipeCLIExecutor` does for every pipe fetch (its tests, `SimpleCLIExecutorTests.swift`, ported).
 */
class PipeCLIExecutorTest {
    private val host = MacProcesses.host
    private val executor = PipeCLIExecutor(host)

    private suspend fun run(binary: String, vararg args: String, timeout: Double = 10.0): CLIResult =
        executor.execute(binary, args.toList(), null, timeout, null, emptyMap())

    private fun path(binaryPath: String): List<String> =
        executor.environment(binaryPath, ProcessEnvironment())["PATH"].orEmpty().split(':')

    // PATH augmentation: a menu bar app launched by launchd gets a minimal PATH; a script CLI
    // with a `/usr/bin/env` shebang (bun, node) needs its runtime findable.

    @Test
    fun `should let a CLI find the runtime that sits beside it when launched from the menu bar`() {
        val entries = path("/test-omp-home/.bun/bin/omp")

        assertEquals(1, entries.count { it == "/test-omp-home/.bun/bin" })
    }

    @Test
    fun `should keep the person's PATH first and add the usual tool folders after it`() {
        val entries = path("/usr/bin/true")

        host.machine.environment["PATH"]?.split(':')?.firstOrNull()?.let { assertEquals(it, entries.first()) }
        val home = host.machine.homeDirectory
        assertTrue("$home/.bun/bin" in entries)
        assertTrue("$home/.local/bin" in entries)
    }

    @Test
    fun `should not add a tool folder the PATH already has`() {
        val entries = path("/opt/homebrew/bin/tool")

        val ambient = host.machine.environment["PATH"].orEmpty().split(':').count { it == "/opt/homebrew/bin" }
        assertEquals(maxOf(ambient, 1), entries.count { it == "/opt/homebrew/bin" })
    }

    // Execution

    @Test
    fun `should give back what the CLI printed and its exit code`() = runBlocking {
        val result = run("/bin/echo", "kiro-output")

        assertTrue("kiro-output" in result.output)
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should report a CLI's failing exit code rather than fail`() = runBlocking {
        assertEquals(7, run("/bin/sh", "-c", "exit 7").exitCode)
    }

    @Test
    fun `should give back what the CLI printed to both output and error`() = runBlocking {
        val result = run("/bin/sh", "-c", "echo out; echo err 1>&2")

        assertTrue("out" in result.output)
        assertTrue("err" in result.output)
    }

    @Test
    fun `should say the CLI is not found when it is not installed`() = runBlocking {
        val error = assertFailsWith<UsageError> { run("claudebar-not-a-real-cli") }

        assertEquals(UsageError.CliNotFound("claudebar-not-a-real-cli"), error)
    }

    /** The data sources' pipe executor reports a timeout as `UsageError.Timeout` (Swift's `PipeCLIExecutor` does too). */
    @Test
    fun `should say the command timed out — near the timeout — when a CLI never finishes`() = runBlocking {
        val start = TimeSource.Monotonic.markNow()

        val error = assertFailsWith<UsageError> { run("/bin/sh", "-c", "sleep 30", timeout = 0.5) }

        assertEquals(UsageError.Timeout, error)
        // Must give up near the timeout, not ride out the full sleep.
        assertTrue(start.elapsedNow().inWholeSeconds < 10)
    }

    @Test
    fun `should give back all of a CLI's output when it prints a lot`() = runBlocking {
        val result = run("/bin/sh", "-c", "seq 1 50000", timeout = 20.0)

        assertEquals(0, result.exitCode)
        assertTrue(result.output.length > 200_000)
    }
}
