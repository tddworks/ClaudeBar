package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The terminal executor end to end: real binaries through a real pseudo-terminal. */
class DefaultCLIExecutorTest {
    private val host = MacProcesses.host

    private suspend fun DefaultCLIExecutor.run(binary: String, args: List<String> = emptyList(), input: String = "", timeout: Double = 20.0, folder: String? = null): CLIResult =
        execute(binary, args, input, timeout, folder, emptyMap())

    @Test
    fun `should show what a CLI printed and its success in a terminal`() = runBlocking {
        val result = DefaultCLIExecutor(host).run("/bin/echo", listOf("pty-hello"))

        assertTrue("pty-hello" in result.output)
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should wait past a quiet spell while Claude's usage screen is still filling in — issue 271`() = runBlocking {
        val result = DefaultCLIExecutor(host, completionRule = usageScreenRule).run(
            "/bin/sh", listOf("-c", "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'"),
        )

        assertTrue("Current session" in result.output)
    }

    @Test
    fun `should still deliver typed input after the stated delay`() = runBlocking {
        val result = DefaultCLIExecutor(host, inputDelay = 1.0).run("/bin/cat", input = "delayed-hello", timeout = 10.0)

        assertTrue("delayed-hello" in result.output)
    }

    @Test
    fun `should fail when the CLI can't be found`() = runBlocking {
        assertFailsWith<Exception> { DefaultCLIExecutor(host).run("claudebar-missing-cli-xyz", timeout = 5.0) }
        Unit
    }

    @Test
    fun `should run the CLI in the folder it is given`() = runBlocking {
        val result = DefaultCLIExecutor(host).run("/bin/pwd", folder = "/tmp")

        assertTrue("tmp" in result.output)
    }

    @Test
    fun `should start the CLI with the extra environment values it is given`() = runBlocking {
        val result = DefaultCLIExecutor(host, environmentAdditions = mapOf("CLAUDEBAR_PROBE" to "1")).run(
            "/bin/sh", listOf("-c", "test \"\$CLAUDEBAR_PROBE\" = 1 && echo marked"),
        )

        assertTrue("marked" in result.output)
    }

    @Test
    fun `should let several CLIs run at once without waiting on each other`() = runBlocking {
        val start = monotonicSeconds()

        val results = (0 until 4).map {
            async { DefaultCLIExecutor(host).run("/bin/sh", listOf("-c", "sleep 1; echo done")) }
        }.awaitAll()

        results.forEach { assertTrue("done" in it.output) }
        val elapsed = monotonicSeconds() - start
        assertTrue(elapsed < 3.0, "took ${elapsed}s")
    }
}
