package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** A variable the app was launched without is still found in the person's login shell (#170), and a found value is not asked for again. */
class ShellEnvironmentTest {
    /** A login shell that prints [value] between the markers. */
    private fun shell(value: String?) = FakeCLIExecutor("/bin/zsh") {
        CLIResult("@@CLAUDEBAR_BEGIN@@${value.orEmpty()}@@CLAUDEBAR_END@@", 0)
    }

    private fun environment(process: Map<String, String>, shell: FakeCLIExecutor) =
        ShellEnvironment(process, LoginShellEnvironment(shell, { emptyMap() }))

    @Test
    fun `should use the app's own environment value without asking the login shell`() {
        val shell = shell("from-shell")
        val environment = environment(mapOf("GLM_KEY" to "from-process"), shell)

        assertEquals("from-process", environment.value("GLM_KEY"))
        assertEquals(0, shell.executions.size)
    }

    @Test
    fun `should find a variable only the login shell exports and ask the shell only once (#170)`() {
        val shell = shell("from-shell")
        val environment = environment(emptyMap(), shell)

        assertEquals("from-shell", environment.value("GLM_KEY"))
        assertEquals("from-shell", environment.value("GLM_KEY"))
        assertEquals(1, shell.executions.size)
    }

    @Test
    fun `should find nothing and ask the login shell again later when the variable is set nowhere`() {
        val shell = shell(null)
        val environment = environment(emptyMap(), shell)

        assertNull(environment.value("GLM_KEY"))
        assertNull(environment.value("GLM_KEY"))
        assertEquals(2, shell.executions.size)
    }
}
