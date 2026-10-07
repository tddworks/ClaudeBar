package com.tddworks.claudebar.providers

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** *Re-auth* for a folder the person chose: the login they run themselves, ready to paste. */
class SignInCommandTest {
    private val codex = TestDefinitions.builtIn("codex")

    @Test
    fun `should give the login a person runs in their own folder`() {
        assertEquals("""CODEX_HOME=/Users/me/.codex-work codex -c 'cli_auth_credentials_store="file"' login""", codex.accounts?.signInCommand("/Users/me/.codex-work"))
    }

    @Test
    fun `should quote a folder with a space so the pasted command still works`() {
        assertEquals("""CODEX_HOME='/Users/me/Work Codex' codex -c 'cli_auth_credentials_store="file"' login""", codex.accounts?.signInCommand("/Users/me/Work Codex"))
    }

    @Test
    fun `should give no command for a provider that has no sign-in`() {
        assertNull(TestDefinitions.builtIn("openrouter").accounts?.signInCommand("/tmp/x"))
    }
}
