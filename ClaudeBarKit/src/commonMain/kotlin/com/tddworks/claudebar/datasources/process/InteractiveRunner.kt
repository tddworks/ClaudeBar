package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.delay

/**
 * Runs a CLI in a pseudo-terminal and captures what it draws. Many CLIs notice when no
 * terminal is attached and print something else; in one they print what a person sees.
 * The capture ends when the program exits, when the screen has settled (idle for 3 s and,
 * under a [CLICompletionRule], showing a ready marker), or at the timeout.
 */
internal class InteractiveRunner(
    private val terminals: PseudoTerminals,
    private val locator: BinaryLocator,
    private val machine: Machine,
    private val files: MachineFiles,
) {
    data class Result(val output: String, val exitCode: Int)

    data class Options(
        val timeout: Double = 20.0,
        /** Where the CLI starts; null inherits the app's folder. */
        val workingDirectory: String? = null,
        val arguments: List<String> = emptyList(),
        /** Prompt text → what to type when it appears — `"Continue? [y/n]": "y\r"`. */
        val autoResponses: Map<String, String> = emptyMap(),
        /** Variables removed from the CLI's environment, so an inherited token can't choose its account. */
        val environmentExclusions: List<String> = emptyList(),
        /**
         * Variables set last, over the terminal defaults; fetches mark their sessions with
         * `CLAUDEBAR_PROBE=1` so ClaudeBar's own hook skips them (#222).
         */
        val environmentAdditions: Map<String, String> = emptyMap(),
        /** Without one any idle gap ends the capture, cutting a TUI that fills in late (#271). */
        val completionRule: CLICompletionRule? = null,
        /** Seconds before [run]'s input is typed, so it lands on a settled TUI screen. */
        val inputDelay: Double = 0.4,
        /** The process tree's quality of service; null is the fetch's own (#204). */
        val qualityOfService: QualityOfService? = null,
    )

    sealed class RunError(message: String) : Exception(message) {
        class BinaryNotFound(val tool: String) : RunError("CLI '$tool' not found. Please install it and ensure it's on PATH.")
        class LaunchFailed(val reason: String) : RunError("Failed to start command: $reason")
        class TimedOut : RunError("Command did not complete within the timeout.")
    }

    /** Runs [binary], types [input], and returns what the terminal received. Exit code -1 while it still runs. */
    suspend fun run(binary: String, input: String, options: Options = Options()): Result {
        val totalStart = monotonicSeconds()
        val findStart = monotonicSeconds()
        val executable = findExecutable(binary)
        AppLog.probes.debug("InteractiveRunner: findExecutable('$binary') took ${(monotonicSeconds() - findStart).secondsText()}s")

        val session = terminals.start(
            executable = executable,
            arguments = options.arguments,
            environment = terminalEnvironment(options.environmentExclusions, options.environmentAdditions),
            workingDirectory = options.workingDirectory,
            quality = qualityOfService(options),
            rows = TERMINAL_ROWS,
            cols = TERMINAL_COLS,
        )
        try {
            val runStart = monotonicSeconds()
            delay((maxOf(0.0, options.inputDelay) * 1000).toLong())
            sendInput(input, session)
            val buffer = captureOutput(session, options)
            AppLog.probes.debug("InteractiveRunner: process execution took ${(monotonicSeconds() - runStart).secondsText()}s")
            val text = utf8OrNull(buffer)
            if (text.isNullOrEmpty()) throw RunError.TimedOut()
            AppLog.probes.debug("InteractiveRunner: total run() took ${(monotonicSeconds() - totalStart).secondsText()}s for '$binary'")
            return Result(text, if (session.isRunning) -1 else session.exitStatus)
        } finally {
            session.close()
        }
    }

    private fun findExecutable(binary: String): String {
        if (files.isExecutable(binary)) return binary
        return locator.which(binary) ?: throw RunError.BinaryNotFound(binary)
    }

    private fun sendInput(input: String, session: TerminalSession) {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return
        session.write((trimmed + "\r").encodeToByteArray())
    }

    private suspend fun captureOutput(session: TerminalSession, options: Options): ByteArray {
        val deadline = monotonicSeconds() + options.timeout
        val buffer = CaptureBuffer()
        var lastMeaningfulData = monotonicSeconds()
        val responses = options.autoResponses.map { it.key.encodeToByteArray() to it.value.encodeToByteArray() }
        val responded = HashSet<String>()

        while (monotonicSeconds() < deadline) {
            val previousSize = buffer.size
            buffer.append(session.read())
            // Only meaningful data restarts the idle clock — a title update is not.
            if (buffer.size > previousSize && isMeaningfulData(buffer.copyFrom(previousSize))) {
                lastMeaningfulData = monotonicSeconds()
            }
            for ((prompt, response) in responses) {
                val key = prompt.decodeToString()
                if (key in responded || !buffer.contains(prompt)) continue
                runCatching { session.write(response) }
                responded += key
                lastMeaningfulData = monotonicSeconds()
            }
            if (!session.isRunning) break
            // Idle on a screen still filling in means "waiting on the network", not "done".
            if (hasMeaningfulContent(buffer.toByteArray()) &&
                monotonicSeconds() - lastMeaningfulData > IDLE_TIMEOUT &&
                !isAwaitingCompletion(buffer.toByteArray(), options.completionRule)
            ) break
            delay(POLL_MILLISECONDS)
        }
        buffer.append(session.read())
        return buffer.toByteArray()
    }

    /** Whether newly received bytes say something — not just an OSC title or bare escapes. */
    private fun isMeaningfulData(data: ByteArray): Boolean {
        val text = utf8OrNull(data) ?: return data.isNotEmpty()
        val stripped = oscSequence.replace(text, "").replace("\u001B", "").replace("\u0007", "")
        return stripped.trim().isNotEmpty()
    }

    /** True while the captured screen is still filling in under [rule]; false without one. */
    fun isAwaitingCompletion(data: ByteArray, rule: CLICompletionRule?): Boolean {
        if (rule == null) return false
        val text = utf8OrNull(data) ?: return false
        return rule.isPending(text)
    }

    /**
     * Whether the capture holds visible text beyond escape sequences — CSI, charset
     * designations, OSC (BEL- or ST-terminated) and lone ESCs. Bytes that aren't UTF-8 count.
     */
    fun hasMeaningfulContent(data: ByteArray): Boolean {
        val text = utf8OrNull(data) ?: return data.isNotEmpty()
        val stripped = oscSequence.replace(
            text.replace(csiSequence, "").replace(charsetSequence, ""),
            "",
        ).replace("\u001B", "")
        return stripped.trim().isNotEmpty()
    }

    /**
     * The app's environment as a terminal session wants it: the login shell's PATH with the
     * Homebrew folders added, defaults for HOME, TERM, COLORTERM, LANG and CI, then the
     * exclusions removed and the additions set.
     */
    private fun terminalEnvironment(excluding: List<String>, additions: Map<String, String>): Map<String, String> {
        val environment = machine.environment.toMutableMap()
        excluding.forEach(environment::remove)
        environment["PATH"] = ensureCommonPathsIncluded(locator.shellPath())
        environment.getOrPut("HOME") { machine.homeDirectory }
        environment.getOrPut("TERM") { "xterm-256color" }
        environment.getOrPut("COLORTERM") { "truecolor" }
        environment.getOrPut("LANG") { "en_US.UTF-8" }
        environment.getOrPut("CI") { "0" }
        environment.putAll(additions)
        return environment
    }

    /**
     * Homebrew's folders, which a login shell's PATH can lack when they are set only in an
     * interactive rc file, put first when they exist.
     */
    private fun ensureCommonPathsIncluded(path: String): String {
        val components = path.split(':').filter { it.isNotEmpty() }.toMutableList()
        for (essential in listOf("/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin").reversed()) {
            if (essential !in components && files.exists(essential)) components.add(0, essential)
        }
        return components.joinToString(":")
    }

    companion object {
        const val TERMINAL_ROWS = 50
        const val TERMINAL_COLS = 160
        private const val IDLE_TIMEOUT = 3.0
        private const val POLL_MILLISECONDS = 60L

        /** OSC — terminal titles, hyperlinks: ESC ] … BEL or ESC ] … ESC \, across lines. */
        private val oscSequence = Regex("\u001B\\].*?(?:\u0007|\u001B\\\\)", RegexOption.DOT_MATCHES_ALL)
        private val csiSequence = Regex("\u001B\\[[0-9;?]*[A-Za-z]")
        private val charsetSequence = Regex("\u001B[()][AB012]")

        /** The quality of service a run will use: the one given, or the fetch's own. */
        suspend fun qualityOfService(options: Options): QualityOfService =
            options.qualityOfService ?: currentQualityOfService()

        /** The text, or null when the bytes aren't valid UTF-8 — as `String(data:encoding:)` answers. */
        fun utf8OrNull(data: ByteArray): String? =
            runCatching { data.decodeToString(throwOnInvalidSequence = true) }.getOrNull()
    }
}

/** A growing byte buffer with the few operations a capture needs. */
internal class CaptureBuffer {
    private var data = ByteArray(8192)
    var size = 0
        private set

    fun append(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        if (size + bytes.size > data.size) data = data.copyOf(maxOf(data.size * 2, size + bytes.size))
        bytes.copyInto(data, size)
        size += bytes.size
    }

    fun copyFrom(start: Int): ByteArray = data.copyOfRange(start, size)

    fun toByteArray(): ByteArray = data.copyOf(size)

    fun contains(needle: ByteArray): Boolean {
        if (needle.isEmpty()) return true
        outer@ for (i in 0..size - needle.size) {
            for (j in needle.indices) if (data[i + j] != needle[j]) continue@outer
            return true
        }
        return false
    }
}
