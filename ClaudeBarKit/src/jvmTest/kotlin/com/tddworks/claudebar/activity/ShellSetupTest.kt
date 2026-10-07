package com.tddworks.claudebar.activity

import com.tddworks.claudebar.providers.TerminalCommand
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.nio.file.Files

/**
 * The shell lines behind *In use*: each `claude` / `codex` reads the login chosen in ClaudeBar
 * and starts on its folder. Written once between markers, removable without touching anything
 * else in the file.
 */
class ShellSetupTest {
    private val home: File = Files.createTempDirectory("shell-setup").toFile()
    private val setup = ShellSetup(
        listOf(
            TerminalCommand("claude", "CLAUDE_CONFIG_DIR"),
            TerminalCommand("codex", "CODEX_HOME"),
            // A second product on the same CLI: wrapped once all the same.
            TerminalCommand("claude", "CLAUDE_CONFIG_DIR"),
        ),
        home.path,
    )

    @AfterEach
    fun cleanUp() {
        home.deleteRecursively()
    }

    // Where

    @Test
    fun `should write each shell's lines to that shell's own startup file`() {
        assertEquals(File(home, ".zshrc").path, setup.file(LoginShell.ZSH))
        assertEquals(File(home, ".bash_profile").path, setup.file(LoginShell.BASH))
        assertEquals(File(home, ".config/fish/conf.d/claudebar-in-use.fish").path, setup.file(LoginShell.FISH))
    }

    @Test
    fun `should set up the person's login shell, zsh when it is unknown`() {
        assertEquals(LoginShell.BASH, LoginShell.login("/bin/bash"))
        assertEquals(LoginShell.FISH, LoginShell.login("/opt/homebrew/bin/fish"))
        assertEquals(LoginShell.ZSH, LoginShell.login("/bin/zsh"))
        assertEquals(LoginShell.ZSH, LoginShell.login(null))
    }

    @Test
    fun `should wrap a CLI once however many products run it`() {
        val lines = setup.lines(LoginShell.ZSH)

        assertEquals(2, lines.split("function claude {").size)
        assertTrue(lines.contains("# ClaudeBar → In use: new claude and codex sessions"))
    }

    // Install and remove

    @Test
    fun `should add one block and keep the rest of the file however often it is installed`() {
        write(".zshrc", "export PATH=\"\$HOME/bin:\$PATH\"\n")

        setup.install(LoginShell.ZSH)
        setup.install(LoginShell.ZSH)

        val text = read(".zshrc")
        assertTrue(text.startsWith("export PATH=\"\$HOME/bin:\$PATH\"\n"))
        assertEquals(2, text.split(ShellSetup.BEGIN).size)
        assertTrue(setup.isInstalled(LoginShell.ZSH))
    }

    @Test
    fun `should create the startup file when there is none`() {
        setup.install(LoginShell.ZSH)

        assertTrue(setup.isInstalled(LoginShell.ZSH))
    }

    @Test
    fun `should take out only ClaudeBar's block when removed`() {
        write(".zshrc", "alias ll='ls -l'\n")
        setup.install(LoginShell.ZSH)
        write(".zshrc", read(".zshrc") + "export EDITOR=vim\n")

        setup.remove(LoginShell.ZSH)

        assertEquals("alias ll='ls -l'\nexport EDITOR=vim\n", read(".zshrc"))
        assertFalse(setup.isInstalled(LoginShell.ZSH))
    }

    @Test
    fun `should give fish a file of its own and delete it when removed`() {
        setup.install(LoginShell.FISH)
        assertTrue(setup.isInstalled(LoginShell.FISH))
        assertTrue(read(".config/fish/conf.d/claudebar-in-use.fish").contains("function claude"))

        setup.remove(LoginShell.FISH)

        assertFalse(File(setup.file(LoginShell.FISH)).exists())
    }

    // What the lines do, run in the real shells

    @ParameterizedTest
    @ValueSource(strings = ["zsh", "bash"])
    fun `should start a new session on the folder chosen in ClaudeBar`(tag: String) {
        val shell = shell(tag)
        setup.install(shell)
        record("claude", "/Users/you/.claude-work")

        assertEquals("CLAUDE_CONFIG_DIR=/Users/you/.claude-work args=--version", run(shell, "claude"))
    }

    @ParameterizedTest
    @ValueSource(strings = ["zsh", "bash"])
    fun `should run the CLI as it always did when nothing is chosen`(tag: String) {
        val shell = shell(tag)
        setup.install(shell)

        assertEquals("CLAUDE_CONFIG_DIR= args=--version", run(shell, "claude"))
        assertEquals("CODEX_HOME=/mine args=--version", run(shell, "codex", environment = mapOf("CODEX_HOME" to "/mine")))
    }

    @ParameterizedTest
    @ValueSource(strings = ["zsh", "bash"])
    fun `should still run the aliased program on the chosen folder when the CLI has an alias`(tag: String) {
        val shell = shell(tag)
        val program = fakeCLI("claude", folder = "local")
        write(if (shell == LoginShell.ZSH) ".zshrc" else ".bash_profile", "alias claude=\"${program.path}\"\n")
        setup.install(shell)
        record("claude", "/Users/you/.claude-work")

        assertEquals("CLAUDE_CONFIG_DIR=/Users/you/.claude-work args=--version", run(shell, "claude", path = false))
    }

    // Helpers

    private fun shell(tag: String): LoginShell = LoginShell.entries.first { it.tag == tag }

    private fun write(name: String, text: String) {
        val file = File(home, name)
        file.parentFile.mkdirs()
        file.writeText(text)
    }

    private fun read(name: String): String = File(home, name).readText()

    private fun record(command: String, folder: String) = write(".claudebar/in-use/$command", folder)

    /** A stand-in CLI that prints the variable it was started with. */
    private fun fakeCLI(name: String, folder: String = "bin"): File {
        val variable = if (name == "claude") "CLAUDE_CONFIG_DIR" else "CODEX_HOME"
        write("$folder/$name", "#!/bin/sh\necho \"$variable=\$$variable args=\$*\"\n")
        return File(home, "$folder/$name").also { it.setExecutable(true) }
    }

    /** Runs `<command> --version` in [shell] with the installed file sourced, as an interactive session would. */
    private fun run(shell: LoginShell, command: String, environment: Map<String, String> = emptyMap(), path: Boolean = true): String {
        if (path) fakeCLI(command)
        val file = setup.file(shell)
        val script = if (shell == LoginShell.BASH) "shopt -s expand_aliases; . '$file'\n$command --version" else ". '$file'\n$command --version"
        val arguments = if (shell == LoginShell.ZSH) listOf("/bin/zsh", "-f", "-c", script) else listOf("/bin/bash", "-c", script)
        val process = ProcessBuilder(arguments).redirectErrorStream(true)
        process.environment().clear()
        process.environment() += mapOf("HOME" to home.path, "PATH" to File(home, "bin").path + ":/usr/bin:/bin") + environment
        val started = process.start()
        val output = started.inputStream.bufferedReader().readText()
        started.waitFor()
        return output.trim()
    }
}
