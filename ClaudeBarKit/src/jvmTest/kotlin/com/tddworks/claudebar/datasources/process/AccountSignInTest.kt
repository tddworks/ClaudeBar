package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.SignInProcess
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource

/**
 * *Sign in with browser*: the vendor's own login, run into a new folder ClaudeBar makes —
 * never an existing one, and nothing left behind when it does not finish.
 */
class AccountSignInTest {
    private val folder = "/accounts/codex/new-login"
    private val call = SignInCall(cli = "codex", args = listOf("login"), homeVariable = "CODEX_HOME", unset = listOf("OPENAI_API_KEY"))

    /** What the login was started with. */
    private class Launch {
        var executable: String? = null
        var arguments: List<String>? = null
        var environment: Map<String, String>? = null
        var directory: String? = null
        var timeout: Double? = null
    }

    private class RecordingProcess(private val launch: Launch = Launch(), private val outcome: () -> Int = { 0 }) : SignInProcess {
        override suspend fun run(executable: String, arguments: List<String>, environment: Map<String, String>, directory: String, timeoutSeconds: Double): Int {
            launch.executable = executable
            launch.arguments = arguments
            launch.environment = environment
            launch.directory = directory
            launch.timeout = timeoutSeconds
            return outcome()
        }
    }

    private fun signIn(process: SignInProcess, folders: InMemoryLoginFolders = InMemoryLoginFolders(), found: Map<String, String> = mapOf("codex" to "/usr/local/bin/codex")) =
        AccountSignIn(process, folders, { found[it] }) { mapOf("PATH" to "/usr/bin", "OPENAI_API_KEY" to "sk-shared", "HOME" to "/Users/me") }

    @Test
    fun `should run the vendor's login in a new folder with only its home variable added`() = runBlocking {
        val launch = Launch()
        val folders = InMemoryLoginFolders()

        signIn(RecordingProcess(launch), folders).signIn(call, folder)

        assertEquals("/usr/local/bin/codex", launch.executable)
        assertEquals(listOf("login"), launch.arguments)
        assertEquals(mapOf("PATH" to "/usr/bin", "HOME" to "/Users/me", "CODEX_HOME" to folder), launch.environment)
        assertEquals(folder, launch.directory)
        assertEquals(300.0, launch.timeout)
        assertEquals(setOf(folder), folders.all)
    }

    @Test
    fun `should make no folder when the CLI is not installed`() {
        val folders = InMemoryLoginFolders()

        val failure = assertThrows<SignInError.CliNotFound> { runBlocking { signIn(RecordingProcess(), folders, found = emptyMap()).signIn(call, folder) } }

        assertEquals(SignInError.CliNotFound("codex"), failure)
        assertTrue(folders.all.isEmpty())
    }

    @Test
    fun `should leave no folder when the login does not finish`() {
        val folders = InMemoryLoginFolders()

        assertThrows<SignInError.DidNotFinish> { runBlocking { signIn(RecordingProcess { 1 }, folders).signIn(call, folder) } }
        assertTrue(folders.all.isEmpty())
    }

    @Test
    fun `should leave no folder when the login times out`() {
        val folders = InMemoryLoginFolders()

        assertThrows<SignInError.TimedOut> { runBlocking { signIn(RecordingProcess { throw SignInError.TimedOut }, folders).signIn(call, folder) } }
        assertTrue(folders.all.isEmpty())
    }

    @Test
    fun `should never sign into a folder that already exists`() {
        val folders = InMemoryLoginFolders(listOf(folder))

        assertThrows<SignInError.FolderExists> { runBlocking { signIn(RecordingProcess(), folders).signIn(call, folder) } }
        assertEquals(setOf(folder), folders.all)
    }

    @Test
    fun `should unset nothing and wait five minutes when the definition gives only the command`() {
        val decoded = SignInCall.from(Json.parseToJsonElement("""{ "cli": "claude", "args": ["auth", "login"], "homeVariable": "CLAUDE_CONFIG_DIR" }"""))

        assertTrue(decoded.unset.isEmpty())
        assertEquals(300.0, decoded.timeout)
    }

    // From the Swift DiskLoginFolders suite: what each error tells the person. The disk itself is DiskLoginFoldersTest (macOS).

    @ParameterizedTest
    @MethodSource("messages")
    fun `should tell the person why the sign-in stopped and what to do next`(error: Exception, message: String) {
        assertEquals(message, error.message)
    }

    companion object {
        @JvmStatic
        fun messages() = listOf(
            arrayOf(SignInError.CliNotFound("codex"), "`codex` wasn't found. Install it, or choose a folder you already signed in to."),
            arrayOf(SignInError.FolderExists, "That folder already exists, so ClaudeBar won't sign in there. Try again."),
            arrayOf(SignInError.DidNotFinish, "Sign-in didn't finish. Try again and complete it in your browser."),
            arrayOf(SignInError.TimedOut, "Sign-in timed out. Try again and complete it in your browser within five minutes."),
        )
    }
}
