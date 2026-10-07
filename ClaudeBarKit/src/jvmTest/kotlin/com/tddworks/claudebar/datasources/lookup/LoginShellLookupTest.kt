package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.definition
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.datasources.thrown
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * `{ "environment": "X", "loginShell": true }` — a key exported only in the person's shell
 * profile is still found when the app starts from Finder (#170). Only a lookup that says so
 * waits for the shell.
 */
class LoginShellLookupTest {
    private val asked = mutableListOf<String>()

    @Test
    fun `should find a key exported only in the login shell when the lookup asks for the shell`() {
        val reader = EnvironmentReader("GLM_KEY", { null }) { name ->
            asked += name
            if (name == "GLM_KEY") "from-shell" else null
        }

        assertEquals("from-shell", reader.find()?.credential?.token)
        assertEquals(listOf("GLM_KEY"), asked)
    }

    @Test
    fun `should read the app's own environment first, without waiting for the shell`() {
        val reader = EnvironmentReader("GLM_KEY", { "from-app" }) { name ->
            asked += name
            "from-shell"
        }

        assertEquals("from-app", reader.find()?.credential?.token)
        assertTrue(asked.isEmpty())
    }

    @Test
    fun `should never ask the shell for a lookup that doesn't say so`() = runTest {
        val sources = testDataSources(loginShell = { name ->
            asked += name
            "from-shell"
        })
        val source = sources.make(definition("""
            {"kind":"api","credential":{"environment":"GLM_KEY"},
             "fetch":{"file":{"path":"~/nowhere.json"}},"mapping":{"json":{"quotas":[]}}}
        """), "acme")

        thrown { source.fetchResponse() }

        assertTrue(asked.isEmpty())
    }

    @Test
    fun `should read and write the lookup as the definition says it`() {
        val shell = lookup("""{"environment":"GLM_KEY","loginShell":true}""")
        val plain = lookup("""{"environment":"GLM_KEY"}""")

        assertEquals(CredentialLookup.Environment("GLM_KEY", loginShell = true), shell)
        assertEquals(CredentialLookup.Environment("GLM_KEY"), plain)
        assertEquals(shell, CredentialLookup.from(shell.toJson()))
        assertEquals("""{"environment":"GLM_KEY"}""", plain.toJson().toString())
    }

    @Test
    fun `should say in the lookup order that the login shell is read too`() {
        assertEquals(listOf("\$GLM_KEY (also your login shell)"), lookup("""{"environment":"GLM_KEY","loginShell":true}""").lookupOrder)
        assertEquals(listOf("\$GLM_KEY"), lookup("""{"environment":"GLM_KEY"}""").lookupOrder)
    }
}
