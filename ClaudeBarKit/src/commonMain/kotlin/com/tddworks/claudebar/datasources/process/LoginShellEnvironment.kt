package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.CancellationException

/**
 * Variables only the person's login shell knows. An app started from Finder or at login
 * inherits launchd's environment, without what `~/.zshrc` or `~/.zprofile` export; when the
 * app's own lookup misses, the login shell is asked.
 */
internal class LoginShellEnvironment(
    private val cliExecutor: CLIExecutor,
    /** The app's environment, for `SHELL`. */
    private val environment: () -> Map<String, String>,
    private val timeoutSeconds: Double = 10.0,
) {
    /** The value, or null when the name is invalid, the lookup fails, or the variable is unset or empty. */
    suspend fun value(name: String): String? {
        if (!isValidName(name)) {
            AppLog.probes.debug("LoginShellEnvironment: invalid variable name, skipping login shell lookup")
            return null
        }
        val shell = environment()["SHELL"].orEmpty()
        val binary = shell.ifEmpty { "/bin/zsh" }
        // An interactive login shell, so the rc files that usually hold the key are sourced.
        val command = "printf '$BEGIN_MARKER%s$END_MARKER\\n' \"\$$name\""
        return try {
            val result = cliExecutor.execute(binary, listOf("-l", "-i", "-c", command), null, timeoutSeconds, null, emptyMap())
            parse(result.output, result.exitCode, name)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            AppLog.probes.debug("LoginShellEnvironment: login shell lookup for $name failed: ${error.message}")
            null
        }
    }

    private fun parse(output: String, exitCode: Int, name: String): String? {
        if (exitCode != 0) {
            AppLog.probes.debug("LoginShellEnvironment: lookup for $name exited with $exitCode")
            return null
        }
        val begin = output.indexOf(BEGIN_MARKER)
        val end = if (begin < 0) -1 else output.indexOf(END_MARKER, begin + BEGIN_MARKER.length)
        if (end < 0) {
            AppLog.probes.debug("LoginShellEnvironment: markers missing from shell output for $name")
            return null
        }
        val value = output.substring(begin + BEGIN_MARKER.length, end).trim()
        if (value.isEmpty()) {
            AppLog.probes.debug("LoginShellEnvironment: $name is not set in login shell")
            return null
        }
        return value
    }

    companion object {
        /**
         * Delimiters around the value, so rc-file noise (a stray `echo`) can't pass for it:
         * `printf` adds no newline, so noise would otherwise run into the value.
         */
        const val BEGIN_MARKER = "@@CLAUDEBAR_BEGIN@@"
        const val END_MARKER = "@@CLAUDEBAR_END@@"

        private val validName = Regex("^[A-Za-z_][A-Za-z0-9_]*$")

        /** The name is put into a shell command, so only an ASCII POSIX identifier passes. */
        fun isValidName(name: String): Boolean = validName.matches(name)
    }
}
