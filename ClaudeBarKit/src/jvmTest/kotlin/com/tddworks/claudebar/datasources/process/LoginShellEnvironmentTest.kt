package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LoginShellEnvironmentTest {
    private fun shell(output: String, exitCode: Int = 0) =
        LoginShellEnvironment(FakeCLIExecutor { CLIResult(output, exitCode) }, environment = { emptyMap() })

    private fun markerWrapped(value: String) = "${LoginShellEnvironment.BEGIN_MARKER}$value${LoginShellEnvironment.END_MARKER}\n"

    // Name validation

    @Test
    fun `should accept conventional environment variable names`() {
        assertTrue(LoginShellEnvironment.isValidName("GLM_AUTH_TOKEN"))
        assertTrue(LoginShellEnvironment.isValidName("_PRIVATE"))
        assertTrue(LoginShellEnvironment.isValidName("z"))
    }

    @Test
    fun `should refuse a variable name that could break out of the shell command`() {
        for (name in listOf("", "9TOKEN", "GLM;rm -rf /", "GLM TOKEN", "GLM\$(touch /tmp/pwned)", "GLM`id`", "GLM_TOKÉN", "TOKEN٣")) {
            assertFalse(LoginShellEnvironment.isValidName(name), name)
        }
    }

    // Value resolution

    @Test
    fun `should find the key the user's shell profile exports`() = runBlocking {
        assertEquals("shell-token", shell(markerWrapped("shell-token")).value("GLM_TOKEN"))
    }

    @Test
    fun `should find no key when the shell profile exports it empty`() = runBlocking {
        assertNull(shell(markerWrapped("")).value("GLM_TOKEN"))
    }

    @Test
    fun `should find no key when the login shell fails`() = runBlocking {
        assertNull(shell(markerWrapped("partial"), exitCode = 1).value("GLM_TOKEN"))
    }

    @Test
    fun `should find no key when the login shell cannot be started`() = runBlocking {
        val failing = LoginShellEnvironment(FakeCLIExecutor { throw UsageError.ExecutionFailed("shell failed") }, environment = { emptyMap() })

        assertNull(failing.value("GLM_TOKEN"))
    }

    @Test
    fun `should never ask the shell for a variable whose name is unsafe`() = runBlocking {
        assertNull(shell("shell-token").value("GLM_TOKEN; rm -rf /"))
    }

    @Test
    fun `should find the key without the whitespace around it`() = runBlocking {
        assertEquals("shell-token", shell(markerWrapped("  shell-token  ")).value("GLM_TOKEN"))
    }

    @Test
    fun `should find the key when the shell profile prints a greeting first`() = runBlocking {
        assertEquals("shell-token", shell("Welcome to zsh\n" + markerWrapped("shell-token")).value("GLM_TOKEN"))
    }

    @Test
    fun `should find no key when the variable is unset and the shell profile prints a greeting`() = runBlocking {
        assertNull(shell("Welcome to zsh\n" + markerWrapped("")).value("GLM_TOKEN"))
    }

    @Test
    fun `should find no key when the shell's answer is not the one ClaudeBar asked for`() = runBlocking {
        assertNull(shell("shell-token\n").value("GLM_TOKEN"))
    }

    @Test
    fun `should find the key only an interactive login shell exports`() = runBlocking {
        val executor = FakeCLIExecutor { run ->
            val interactive = "-i" in run.args && run.args.any { "\"\$GLM_TOKEN\"" in it }
            if (interactive) CLIResult(markerWrapped("shell-token")) else CLIResult("", 1)
        }

        assertEquals("shell-token", LoginShellEnvironment(executor, environment = { emptyMap() }).value("GLM_TOKEN"))
    }
}
