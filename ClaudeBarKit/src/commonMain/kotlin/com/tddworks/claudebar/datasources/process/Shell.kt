package com.tddworks.claudebar.datasources.process

/** How each login shell is asked where a CLI lives and what its PATH is, and how its answer reads. */
internal enum class Shell {
    POSIX,
    FISH,
    NUSHELL;

    fun whichArguments(tool: String): List<String> {
        val safe = sanitized(tool) ?: return listOf("-l", "-c", "which ''")
        return when (this) {
            POSIX, FISH -> listOf("-l", "-c", "which $safe")
            // ^which calls the external binary, not Nushell's table-printing built-in.
            NUSHELL -> listOf("-l", "-c", "^which $safe")
        }
    }

    fun pathArguments(): List<String> = when (this) {
        POSIX, FISH -> listOf("-l", "-c", "echo \$PATH")
        NUSHELL -> listOf("-l", "-c", "\$env.PATH | str join ':'")
    }

    fun parseWhichOutput(output: String): String? {
        val cleaned = stripEscapeSequences(output).trim()
        if (cleaned.isEmpty()) return null
        return when (this) {
            POSIX, FISH -> cleaned
            // A table leaked through: no path in it is trusted.
            NUSHELL -> if (cleaned.any { it in TABLE_CHARACTERS }) null else cleaned
        }
    }

    fun parsePathOutput(output: String): String = stripEscapeSequences(output).trim()

    companion object {
        private const val TABLE_CHARACTERS = "│╭╮╯╰─┼┤├┬┴┌┐└┘"
        private val toolName = Regex("^[A-Za-z0-9._-]+$")

        fun detect(shellPath: String): Shell = when (shellPath.substringAfterLast('/').lowercase()) {
            "nu", "nushell" -> NUSHELL
            "fish" -> FISH
            else -> POSIX
        }

        /** The shell `SHELL` names, `/bin/zsh` when it names none. */
        fun current(environment: Map<String, String>): Shell = detect(environment["SHELL"] ?: "/bin/zsh")

        /** A name the shell can't read as more than a name. */
        private fun sanitized(tool: String): String? = tool.takeIf { toolName.matches(it) }

        /**
         * Without the OSC sequences terminal shell integration (iTerm2) injects — with or
         * without their ESC — and plain CSI sequences.
         */
        private fun stripEscapeSequences(text: String): String = text
            .replace(Regex("\u001B\\].*?(?:\u001B\\\\|\u0007)"), "")
            .replace(Regex("\\]\\d+;[^\n]*?(?=/|$)"), "")
            .replace(Regex("\u001B\\[[0-9;]*[A-Za-z]"), "")
    }
}
