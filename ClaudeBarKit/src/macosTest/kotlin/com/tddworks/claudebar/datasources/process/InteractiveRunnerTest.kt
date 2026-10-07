package com.tddworks.claudebar.datasources.process

import kotlinx.coroutines.runBlocking
import platform.posix.setenv
import platform.posix.unsetenv
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Real CLIs in a real pseudo-terminal. What counts as meaningful output is `HasMeaningfulContentTest` (JVM). */
@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
class InteractiveRunnerTest {
    private val host = MacProcesses.host
    private val runner = InteractiveRunner(host.terminals, host.locator, host.machine, host.files)

    @Test
    fun `should show what a CLI printed and its success`() = runBlocking {
        val result = runner.run("/bin/echo", "", InteractiveRunner.Options(arguments = listOf("hello")))

        assertEquals(0, result.exitCode)
        assertTrue("hello" in result.output)
    }

    @Test
    fun `should fail when the CLI isn't installed`() = runBlocking {
        assertFailsWith<InteractiveRunner.RunError> { runner.run("unknown-binary-xyz-123", "") }
        Unit
    }

    @Test
    fun `should keep every environment value for a CLI unless told otherwise`() {
        assertTrue(InteractiveRunner.Options().environmentExclusions.isEmpty())
    }

    @Test
    fun `should remember which environment values to keep from a CLI`() {
        val options = InteractiveRunner.Options(environmentExclusions = listOf("CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"))

        assertEquals(listOf("CLAUDE_CODE_OAUTH_TOKEN", "OTHER_VAR"), options.environmentExclusions)
    }

    @Test
    fun `should start the CLI without the environment values it is told to drop`() = runBlocking {
        val key = "CLAUDEBAR_TEST_EXCLUSION_VAR"
        setenv(key, "should_be_stripped", 1)
        try {
            val result = runner.run("/usr/bin/env", "", InteractiveRunner.Options(environmentExclusions = listOf(key)))

            assertFalse("CLAUDEBAR_TEST_EXCLUSION_VAR=should_be_stripped" in result.output)
        } finally {
            unsetenv(key)
        }
    }

    @Test
    fun `should start the CLI with this app's environment values when none are dropped`() = runBlocking {
        val key = "CLAUDEBAR_TEST_PRESERVE_VAR"
        setenv(key, "should_be_present", 1)
        try {
            val result = runner.run("/usr/bin/env", "", InteractiveRunner.Options())

            assertTrue("CLAUDEBAR_TEST_PRESERVE_VAR=should_be_present" in result.output)
        } finally {
            unsetenv(key)
        }
    }

    @Test
    fun `should add no environment values for a CLI unless told to`() {
        assertTrue(InteractiveRunner.Options().environmentAdditions.isEmpty())
    }

    @Test
    fun `should start the CLI with the extra environment values it is given — issue 222`() = runBlocking {
        val result = runner.run("/usr/bin/env", "", InteractiveRunner.Options(environmentAdditions = mapOf("CLAUDEBAR_PROBE" to "1")))

        assertTrue("CLAUDEBAR_PROBE=1" in result.output)
    }

    @Test
    fun `should wait on no screen rule unless one is given`() {
        assertNull(InteractiveRunner.Options().completionRule)
    }

    @Test
    fun `should remember the screen rule it is given`() {
        assertEquals(usageScreenRule, InteractiveRunner.Options(completionRule = usageScreenRule).completionRule)
    }

    @Test
    fun `should keep waiting past a quiet spell while Claude's usage screen shows only its placeholder — issue 271`() = runBlocking {
        val script = "printf 'Loading usage data...'; sleep 5; printf 'Current session 1%% used'"

        val result = runner.run("/bin/sh", "", InteractiveRunner.Options(timeout = 20.0, arguments = listOf("-c", script), completionRule = usageScreenRule))

        assertTrue("Current session" in result.output)
    }

    @Test
    fun `should keep waiting past a quiet spell while the CLI is still booting — issue 317`() = runBlocking {
        val script = """
            printf 'Opus 5 (1M context) with high effort · API Usage Billing\n'
            printf '~/Library/Application Support/ClaudeBar/Probe\n'
            printf '\xe2\x9d\xaf /usage\n'
            printf '✢ Burrowing… (running SessionStart hooks… 2/5 · 0s)\n'
            printf ' Esc to cancel\n'
            sleep 5
            printf 'Current session 1%% used\n'
        """.trimIndent()

        val result = runner.run("/bin/sh", "", InteractiveRunner.Options(timeout = 20.0, arguments = listOf("-c", script), completionRule = usageScreenRule))

        assertTrue("Current session" in result.output)
    }

    @Test
    fun `should stop at once on a finished usage screen rather than wait out the timeout`() = runBlocking {
        val script = "printf 'Current session 1%% used'; sleep 15"

        val result = runner.run("/bin/sh", "", InteractiveRunner.Options(timeout = 20.0, arguments = listOf("-c", script), completionRule = usageScreenRule))

        assertTrue("Current session" in result.output)
        // -1 while the program still runs: the run returned early, whatever the clock says.
        assertEquals(-1, result.exitCode)
    }
}
