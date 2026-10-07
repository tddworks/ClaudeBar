package com.tddworks.claudebar.datasources.process

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Programs over pipes, against real programs: the failure modes guarded here — a pipe-buffer
 * deadlock, an unreaped child, a lost exit code — only show against a real process.
 */
class SubprocessSupportTest {
    private val processes = PosixSubprocesses

    @Test
    fun `should hear what a program prints at every quality of service`() = runBlocking {
        for (quality in listOf(QualityOfService.USER_INTERACTIVE, QualityOfService.USER_INITIATED, QualityOfService.UTILITY, QualityOfService.BACKGROUND, QualityOfService.DEFAULT)) {
            val result = processes.run("/bin/echo", listOf("hello"), quality = quality)

            assertEquals("hello", result.standardOutput.trim(), "$quality")
            assertEquals(0, result.exitCode)
            assertTrue(result.isSuccess)
        }
    }

    @Test
    fun `should report a failing program's exit code without failing the run`() = runBlocking {
        val result = processes.run("/usr/bin/false", emptyList())

        assertTrue(result.exitCode != 0)
        assertFalse(result.isSuccess)
    }

    @Test
    fun `should hear a program's errors apart from what it prints`() = runBlocking {
        val result = processes.run("/bin/sh", listOf("-c", "echo out; echo err 1>&2; exit 3"))

        assertTrue("out" in result.standardOutput)
        assertTrue("err" in result.standardError)
        assertFalse("err" in result.standardOutput)
        assertEquals(3, result.exitCode)
    }

    @Test
    fun `should hand a program the input it is given`() = runBlocking {
        val result = processes.run("/bin/cat", emptyList(), input = "piped-value")

        assertEquals("piped-value", result.standardOutput)
    }

    @Test
    fun `should not leave a program waiting for input when there is none`() = runBlocking {
        val result = processes.run("/bin/cat", emptyList())

        assertTrue(result.standardOutput.isEmpty())
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should hear everything a program prints when it is far more than a pipe holds`() = runBlocking {
        val result = processes.run("/bin/sh", listOf("-c", "seq 1 50000"))

        assertEquals(0, result.exitCode)
        assertTrue(result.standardOutput.length > 200_000)
        assertTrue(result.standardOutput.startsWith("1\n"))
        assertTrue(result.standardOutput.endsWith("50000\n"))
    }

    @Test
    fun `should report a program killed by a signal as failed`() = runBlocking {
        val result = processes.run("/bin/sh", listOf("-c", "kill -TERM \$\$"))

        assertFalse(result.isSuccess)
    }

    @Test
    fun `should fail when the program does not exist`() = runBlocking {
        assertFailsWith<Exception> { processes.run("/nonexistent/claudebar-not-a-binary", emptyList()) }
        Unit
    }

    @Test
    fun `should run a program in the folder it is asked to`() = runBlocking {
        val result = processes.run("/bin/pwd", emptyList(), workingDirectory = "/tmp")

        assertTrue("tmp" in result.standardOutput)
    }

    @Test
    fun `should stop the program promptly when its run is cancelled`() = runBlocking {
        val run = async(Dispatchers.Default) { processes.run("/bin/sh", listOf("-c", "sleep 30")) }
        delay(200)

        val start = monotonicSeconds()
        run.cancel()
        runCatching { run.await() }
        val elapsed = monotonicSeconds() - start

        assertTrue(elapsed < 10, "took ${elapsed}s")
    }
}
