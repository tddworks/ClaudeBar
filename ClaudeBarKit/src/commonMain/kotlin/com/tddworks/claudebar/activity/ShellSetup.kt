package com.tddworks.claudebar.activity

import com.tddworks.claudebar.providers.TerminalCommand
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString

/**
 * The shell lines behind *In use* ([ShellLines] on disk): a function per CLI that reads the
 * login chosen in ClaudeBar (`~/.claudebar/in-use/<command>`, see `LoginsInUse`) and starts the
 * CLI on that folder. An empty record runs the CLI exactly as before. The lines live between
 * two markers, so installing twice writes them once and removing takes out nothing else; fish
 * gets a file of its own.
 */
internal class ShellSetup(commands: List<TerminalCommand>, val home: String) : ShellLines {
    /** A CLI is wrapped once, however many products run it. */
    val commands: List<TerminalCommand> = commands.distinctBy { it.name }

    /** Where the lines go. Terminal on macOS starts bash as a login shell, which reads `.bash_profile`. */
    override fun file(shell: LoginShell): String = when (shell) {
        LoginShell.ZSH -> Path(home, ".zshrc")
        LoginShell.BASH -> Path(home, ".bash_profile")
        LoginShell.FISH -> Path(home, ".config", "fish", "conf.d", "claudebar-in-use.fish")
    }.toString()

    override fun isInstalled(shell: LoginShell): Boolean = read(file(shell))?.contains(BEGIN) ?: false

    /** The lines, as the setup sheet shows them and [install] writes them. */
    override fun lines(shell: LoginShell): String {
        val existing = read(file(shell)) ?: ""
        val body = commands.map { command ->
            val name = command.name
            val record = "\$HOME/.claudebar/in-use/$name"
            if (shell == LoginShell.FISH) {
                listOf(
                    "function $name",
                    "    set -l d (cat \"$record\" 2>/dev/null)",
                    "    if test -n \"\$d\"",
                    "        ${command.variable}=\$d command $name \$argv",
                    "    else",
                    "        command $name \$argv",
                    "    end",
                    "end",
                ).joinToString("\n")
            } else {
                // An alias always wins over a function, so one for this CLI is replaced, and
                // the function runs the program it named.
                val alias = alias(name, removingBlock(existing))
                val program = alias ?: "command $name"
                (if (alias == null) "" else "unalias $name 2>/dev/null\n") + listOf(
                    "function $name {",
                    "  local d; d=\"\$(cat \"$record\" 2>/dev/null)\"",
                    "  if [ -n \"\$d\" ]; then ${command.variable}=\"\$d\" $program \"\$@\"; else $program \"\$@\"; fi",
                    "}",
                ).joinToString("\n")
            }
        }
        val names = commands.joinToString(" and ") { it.name }
        return listOf(
            BEGIN,
            "# ClaudeBar → In use: new $names sessions start on the login chosen in ClaudeBar.",
            "# Delete this block, or turn it off in ClaudeBar's Settings, to go back.",
            body.joinToString("\n"),
            END,
            "",
        ).joinToString("\n")
    }

    /** Writes the block, replacing any earlier one, and keeps the rest of the file. */
    override fun install(shell: LoginShell) {
        val path = file(shell)
        Path(path).parent?.let { SystemFileSystem.createDirectories(it) }
        val block = lines(shell)
        val rest = removingBlock(read(path) ?: "")
        val text = if (shell == LoginShell.FISH) block
        else rest + (if (rest.isEmpty() || rest.endsWith("\n")) "" else "\n") + block
        write(path, text)
    }

    /** Takes the block out — and fish's own file with it. */
    override fun remove(shell: LoginShell) {
        val path = file(shell)
        val text = read(path) ?: return
        if (shell == LoginShell.FISH) SystemFileSystem.delete(Path(path)) else write(path, removingBlock(text))
    }

    private fun read(path: String): String? =
        runCatching { SystemFileSystem.source(Path(path)).buffered().use { it.readString() } }.getOrNull()

    /** Written whole and renamed into place, as Foundation's atomic write does. */
    private fun write(path: String, text: String) {
        val writing = Path("$path.writing")
        SystemFileSystem.sink(writing).buffered().use { it.writeString(text) }
        SystemFileSystem.atomicMove(writing, Path(path))
    }

    companion object {
        const val BEGIN = "# >>> claudebar in-use >>>"
        const val END = "# <<< claudebar in-use <<<"

        /** The program an `alias name=…` line in [text] runs, the last one winning. */
        fun alias(name: String, text: String): String? {
            val pattern = Regex("""(?m)^\s*alias\s+""" + Regex.escape(name) + """=(['"]?)(.+?)\1\s*$""")
            return pattern.findAll(text).lastOrNull()?.groupValues?.get(2)
        }

        /** The text without ClaudeBar's block. */
        fun removingBlock(text: String): String {
            val start = text.indexOf(BEGIN)
            if (start < 0) return text
            val end = text.indexOf(END, start + BEGIN.length)
            if (end < 0) return text
            var after = end + END.length
            if (after < text.length && text[after] == '\n') after++
            return text.substring(0, start) + text.substring(after)
        }
    }
}
