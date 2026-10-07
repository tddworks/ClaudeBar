package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class ShellTest {
    private val noLookup = listOf("-l", "-c", "which ''")

    // Detection

    @Test
    fun `should recognise nushell from its path`() {
        assertEquals(Shell.NUSHELL, Shell.detect("/opt/homebrew/bin/nu"))
        assertEquals(Shell.NUSHELL, Shell.detect("/usr/local/bin/nushell"))
        assertEquals(Shell.NUSHELL, Shell.detect("/home/user/.nix-profile/bin/nu"))
    }

    @Test
    fun `should recognise nushell whatever the case of its name`() {
        assertEquals(Shell.NUSHELL, Shell.detect("/bin/Nu"))
        assertEquals(Shell.NUSHELL, Shell.detect("/bin/NUSHELL"))
    }

    @Test
    fun `should recognise fish from its path`() {
        assertEquals(Shell.FISH, Shell.detect("/opt/homebrew/bin/fish"))
        assertEquals(Shell.FISH, Shell.detect("/usr/local/bin/fish"))
        assertEquals(Shell.FISH, Shell.detect("/usr/bin/fish"))
    }

    @Test
    fun `should treat zsh, bash and sh as POSIX shells`() {
        for (path in listOf("/bin/zsh", "/bin/bash", "/bin/sh", "/usr/local/bin/zsh", "/opt/homebrew/bin/bash")) {
            assertEquals(Shell.POSIX, Shell.detect(path), path)
        }
    }

    @Test
    fun `should treat a shell it does not know as POSIX`() {
        assertEquals(Shell.POSIX, Shell.detect("/some/unknown/shell"))
        assertEquals(Shell.POSIX, Shell.detect("/bin/ksh"))
        assertEquals(Shell.POSIX, Shell.detect("/bin/dash"))
    }

    // Commands

    @Test
    fun `should ask a POSIX login shell where a CLI lives with which`() {
        assertEquals(listOf("-l", "-c", "which claude"), Shell.POSIX.whichArguments("claude"))
    }

    @Test
    fun `should ask fish where a CLI lives with which`() {
        assertEquals(listOf("-l", "-c", "which codex"), Shell.FISH.whichArguments("codex"))
    }

    @Test
    fun `should ask nushell where a CLI lives with the external which`() {
        assertEquals(listOf("-l", "-c", "^which claude"), Shell.NUSHELL.whichArguments("claude"))
    }

    @Test
    fun `should look up a CLI whose name has dots and hyphens`() {
        assertEquals(listOf("-l", "-c", "which my-tool.sh"), Shell.POSIX.whichArguments("my-tool.sh"))
    }

    @Test
    fun `should look up nothing when a CLI name holds shell metacharacters`() {
        assertEquals(noLookup, Shell.POSIX.whichArguments("claude; rm -rf /"))
        assertEquals(noLookup, Shell.POSIX.whichArguments("\$(whoami)"))
        assertEquals(noLookup, Shell.POSIX.whichArguments("`id`"))
        assertEquals(noLookup, Shell.POSIX.whichArguments("tool'injection"))
        assertEquals(noLookup, Shell.POSIX.whichArguments("tool with spaces"))
        assertEquals(noLookup, Shell.NUSHELL.whichArguments("claude; rm -rf /"))
    }

    @Test
    fun `should ask a POSIX login shell for its PATH`() {
        assertEquals(listOf("-l", "-c", "echo \$PATH"), Shell.POSIX.pathArguments())
    }

    @Test
    fun `should ask fish for its PATH`() {
        assertEquals(listOf("-l", "-c", "echo \$PATH"), Shell.FISH.pathArguments())
    }

    @Test
    fun `should ask nushell for its PATH joined with colons`() {
        assertEquals(listOf("-l", "-c", "\$env.PATH | str join ':'"), Shell.NUSHELL.pathArguments())
    }

    // Output

    @Test
    fun `should find the CLI where a POSIX shell says it lives`() {
        assertEquals("/usr/local/bin/claude", Shell.POSIX.parseWhichOutput("/usr/local/bin/claude\n"))
    }

    @Test
    fun `should find the CLI when a POSIX shell pads its path with whitespace`() {
        assertEquals("/usr/local/bin/claude", Shell.POSIX.parseWhichOutput("  /usr/local/bin/claude  \n"))
    }

    @Test
    fun `should find no CLI when a POSIX shell prints nothing`() {
        assertNull(Shell.POSIX.parseWhichOutput(""))
        assertNull(Shell.POSIX.parseWhichOutput("   \n"))
    }

    @Test
    fun `should find the CLI where fish says it lives`() {
        assertEquals("/opt/homebrew/bin/gemini", Shell.FISH.parseWhichOutput("/opt/homebrew/bin/gemini\n"))
    }

    @Test
    fun `should find the CLI where nushell says it lives`() {
        assertEquals("/Users/user/.local/bin/claude", Shell.NUSHELL.parseWhichOutput("/Users/user/.local/bin/claude\n"))
    }

    @Test
    fun `should find no CLI when nushell prints a table instead of a path`() {
        val table = """
            ╭───┬─────────┬─────────────────────────────────────────────────────┬──────────╮
            │ # │ command │                        path                         │   type   │
            ├───┼─────────┼─────────────────────────────────────────────────────┼──────────┤
            │ 0 │ claude  │ /Users/user/.local/bin/claude                       │ external │
            ╰───┴─────────┴─────────────────────────────────────────────────────┴──────────╯
        """.trimIndent()

        assertNull(Shell.NUSHELL.parseWhichOutput(table))
    }

    @Test
    fun `should find no CLI when nushell prints part of a table`() {
        assertNull(Shell.NUSHELL.parseWhichOutput("│ some output"))
        assertNull(Shell.NUSHELL.parseWhichOutput("╭───"))
        assertNull(Shell.NUSHELL.parseWhichOutput("╰───╯"))
    }

    @Test
    fun `should find no CLI when the answer holds any table box-drawing character`() {
        for (answer in listOf("╮───", "╯───", "path─with─box", "├──┼──┤", "─┬─", "─┴─", "┌──┐", "└──┘")) {
            assertNull(Shell.NUSHELL.parseWhichOutput(answer), answer)
        }
    }

    @Test
    fun `should read the login shell's PATH without the whitespace around it`() {
        val output = "  /usr/bin:/bin:/usr/local/bin  \n"

        assertEquals("/usr/bin:/bin:/usr/local/bin", Shell.POSIX.parsePathOutput(output))
        assertEquals("/usr/bin:/bin:/usr/local/bin", Shell.NUSHELL.parsePathOutput(output))
    }

    // The current shell

    @Test
    fun `should use the shell the SHELL environment variable names`() {
        val environment = System.getenv()

        assertEquals(Shell.detect(environment["SHELL"] ?: "/bin/zsh"), Shell.current(environment))
    }
}
