package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * Guest passes, read by the generic worker from Claude's `guestPasses` block in `claude.json`:
 * `claude /passes` copies the referral link to the clipboard, or prints it with the count.
 */
class CLIGuestPassSourceTest {
    /** Claude's block, as the bundle ships it. */
    private val command = TestDefinitions.builtIn("claude").guestPasses!!

    /** A CLI found where [located] says, that answers every run with [output] (or [failure]). */
    private class CLI(
        private val output: String = "",
        private val failure: Exception? = null,
        private val located: (String) -> String? = { "/usr/local/bin/claude" },
    ) : CLIExecutor {
        val runs = mutableListOf<List<String>>()

        override fun locate(binary: String): String? = located(binary)

        override suspend fun execute(
            binary: String,
            args: List<String>,
            input: String?,
            timeoutSeconds: Double,
            workingDirectory: String?,
            autoResponses: Map<String, String>,
        ): CLIResult {
            runs += listOf(binary) + args
            failure?.let { throw it }
            return CLIResult(output, 0)
        }
    }

    private fun source(cli: CLI, clipboard: String? = null, binary: String = "claude") =
        CLIGuestPassSource(command, { binary }, cli, { clipboard })

    // Parsing (a screen that shows the link)

    @Test
    fun `should show 3 guest passes left and the referral link when Claude lists them`() {
        val output = """
        Guest passes · 3 left

          ┌──────────┐ ┌──────────┐ ┌──────────┐
           ) CC ✻ ┊ (   ) CC ✻ ┊ (   ) CC ✻ ┊ (
          └──────────┘ └──────────┘ └──────────┘

          https://claude.ai/referral/DJ_kWX90Xw

          Share a free week of Claude Code with friends.
        """.trimIndent()

        val pass = command.parse(output)

        assertEquals(3L, pass.passesRemaining)
        assertEquals("https://claude.ai/referral/DJ_kWX90Xw", pass.referralURL)
    }

    @Test
    fun `should show 1 guest pass left and the referral link when Claude lists one`() {
        val output = """
        Guest passes · 1 left

          ┌──────────┐
           ) CC ✻ ┊ (
          └──────────┘

          https://claude.ai/referral/ABC123

          Share a free week of Claude Code with friends.
        """.trimIndent()

        val pass = command.parse(output)

        assertEquals(1L, pass.passesRemaining)
        assertEquals("https://claude.ai/referral/ABC123", pass.referralURL)
    }

    @Test
    fun `should show no guest passes left but still the referral link when Claude has none to give`() {
        val output = """
        Guest passes · 0 left

          https://claude.ai/referral/XYZ789

          Share a free week of Claude Code with friends.
        """.trimIndent()

        val pass = command.parse(output)

        assertEquals(0L, pass.passesRemaining)
        assertEquals("https://claude.ai/referral/XYZ789", pass.referralURL)
    }

    @Test
    fun `should show the referral link with no count when Claude prints only the link`() {
        val output = """
        https://claude.ai/referral/ABC123

        Share a free week of Claude Code with friends.
        """.trimIndent()

        val pass = command.parse(output)

        assertNull(pass.passesRemaining)
        assertEquals("https://claude.ai/referral/ABC123", pass.referralURL)
    }

    @Test
    fun `should fail when Claude prints no referral link`() {
        val output = """
        Guest passes · 3 left

          Share a free week of Claude Code with friends.
        """.trimIndent()

        assertThrows<UsageError> { command.parse(output) }
    }

    @Test
    fun `should read the pass count and link through Claude's terminal colors`() {
        val output = "\u001B[1mGuest passes\u001B[0m · \u001B[32m3 left\u001B[0m\n\nhttps://claude.ai/referral/ABC123"

        val pass = command.parse(output)

        assertEquals(3L, pass.passesRemaining)
        assertEquals("https://claude.ai/referral/ABC123", pass.referralURL)
    }

    // Running the command (the link on the screen)

    @Test
    fun `should show the pass count and referral link Claude prints for -passes`() = runBlocking {
        val cli = CLI(
            """
            Guest passes · 2 left

              https://claude.ai/referral/TEST123

              Share a free week of Claude Code with friends.
            """.trimIndent(),
        )

        val pass = source(cli).fetch()

        assertEquals(2L, pass.passesRemaining)
        assertEquals("https://claude.ai/referral/TEST123", pass.referralURL)
        assertEquals(listOf("claude", "/passes", "--allowed-tools", ""), cli.runs.single())
    }

    // Running the command (the link on the clipboard — today's CLI)

    @Test
    fun `should take the referral link from the clipboard when Claude only copies it there`() = runBlocking {
        val cli = CLI("> /passes\n  ⎿  Referral link copied to clipboard!")

        val pass = source(cli, clipboard = "https://claude.ai/referral/CLIPBOARD123").fetch()

        assertNull(pass.passesRemaining)
        assertEquals("https://claude.ai/referral/CLIPBOARD123", pass.referralURL)
    }

    @Test
    fun `should fail when the referral link is neither printed nor on the clipboard`() {
        val cli = CLI("> /passes\n  ⎿  Referral link copied to clipboard!")

        assertThrows<UsageError> { runBlocking { source(cli, clipboard = "Some other clipboard content").fetch() } }
    }

    @Test
    fun `should offer guest passes when the Claude CLI is installed`() = runBlocking {
        assertTrue(source(CLI()).isAvailable())
    }

    @Test
    fun `should not offer guest passes when the Claude CLI is not installed`() = runBlocking {
        assertFalse(source(CLI(located = { null })).isAvailable())
    }

    @Test
    fun `should fail when the Claude CLI fails to run`() {
        val cli = CLI(failure = UsageError.ExecutionFailed("CLI error"))

        val error = assertThrows<UsageError> { runBlocking { source(cli).fetch() } }

        assertEquals(UsageError.ExecutionFailed("CLI error"), error)
    }

    @Test
    fun `should offer guest passes when the Claude CLI lives at the location the person chose`() = runBlocking {
        val cli = CLI(located = { if (it == "/opt/tools/bin/claude-work") it else null })

        assertTrue(source(cli, binary = "/opt/tools/bin/claude-work").isAvailable())
    }

    // The block itself — new with the definition, which now carries what the Swift source hard-coded

    @Test
    fun `should fail when the screen does not say the command worked`() {
        val cli = CLI("Unknown command: /passes")

        val error = assertThrows<UsageError> { runBlocking { source(cli, clipboard = "https://claude.ai/referral/X").fetch() } }

        assertEquals(UsageError.ParseFailed("Command did not indicate success"), error)
    }

    @Test
    fun `should not read the clipboard when the definition says the link is printed`() {
        val printed = command.copy(clipboard = false)
        val cli = CLI("Referral link copied to clipboard!")

        assertThrows<UsageError> {
            runBlocking { CLIGuestPassSource(printed, { "claude" }, cli, { "https://claude.ai/referral/X" }).fetch() }
        }
    }

    @Test
    fun `should keep a definition's guest passes when it is written out and read back`() {
        val again = GuestPassCommand.from(Json.parseToJsonElement(command.toJson().toString()))

        assertEquals(command, again)
    }

    @Test
    fun `should refuse a guest passes block without a link to read`() {
        assertThrows<DefinitionError> { GuestPassCommand.from(Json.parseToJsonElement("""{"args":["/passes"]}""")) }
    }
}
