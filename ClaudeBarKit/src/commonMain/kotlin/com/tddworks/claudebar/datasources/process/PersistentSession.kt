package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * One long-lived terminal session that several commands are typed into, for a CLI whose
 * startup (trust prompts, initialisation) costs more than the command. [InteractiveRunner]
 * starts a process per command instead. Its calls take turns.
 */
internal class PersistentSession(private val config: Config, private val host: ProcessHost) {
    sealed class SessionError(message: String) : Exception(message) {
        class BinaryNotFound(val tool: String) : SessionError("CLI '$tool' not found. Please install it and ensure it's on PATH.")
        class LaunchFailed(val reason: String) : SessionError("Failed to start session: $reason")
        class NotStarted : SessionError("Session has not been started. Call start() first.")
        class Died : SessionError("Session process has terminated unexpectedly.")
        class TimedOut : SessionError("Command did not complete within the timeout.")
        class InvalidOutput : SessionError("Could not decode output from session.")
    }

    data class Config(
        val binary: String,
        val arguments: List<String> = emptyList(),
        val workingDirectory: String? = null,
        /** Prompt text → what to type when it appears during startup. */
        val autoResponses: Map<String, String> = emptyMap(),
        val commandTimeout: Double = 15.0,
        val startupTimeout: Double = 30.0,
    )

    private val turns = Mutex()
    private var session: TerminalSession? = null
    private var isStarted = false

    /** The prompt the CLI shows when it is ready for a command. */
    private val readyMarker = "❯"

    val isRunning: Boolean get() = session?.isRunning ?: false

    /** Starts the CLI and waits for its prompt. */
    suspend fun start() = turns.withLock {
        if (isStarted && isRunning) {
            AppLog.probes.debug("PersistentSession: already running")
            return@withLock
        }
        AppLog.probes.info("PersistentSession: starting ${config.binary}...")
        val executable = host.locator.which(config.binary) ?: throw SessionError.BinaryNotFound(config.binary)
        val started = try {
            host.terminals.start(
                executable, config.arguments, terminalEnvironment(), config.workingDirectory,
                currentQualityOfService(), TERMINAL_ROWS, TERMINAL_COLS,
            )
        } catch (failed: InteractiveRunner.RunError.LaunchFailed) {
            throw SessionError.LaunchFailed(failed.reason)
        } catch (failed: Exception) {
            throw SessionError.LaunchFailed(failed.message ?: failed.toString())
        }
        session = started
        isStarted = true
        AppLog.probes.debug("PersistentSession: waiting for CLI to be ready...")
        waitForReady(started)
        AppLog.probes.info("PersistentSession: CLI is ready")
    }

    /** Types [command] and returns what the CLI answered. A slash command is typed slowly, for its autocomplete. */
    suspend fun sendCommand(command: String, timeout: Double? = null): String = turns.withLock {
        if (!isStarted) throw SessionError.NotStarted()
        val running = session?.takeIf { it.isRunning } ?: throw SessionError.Died()
        AppLog.probes.debug("PersistentSession: sending command '$command'")
        running.read()
        if (command.startsWith("/")) {
            for (character in command) {
                running.write(character.toString().encodeToByteArray())
                delay(50)
            }
            delay(1000)
            running.write("\r".encodeToByteArray())
            AppLog.probes.debug("PersistentSession: sent Enter after slash command")
        } else {
            running.write("$command\r".encodeToByteArray())
        }
        val output = captureCommandOutput(running, timeout ?: config.commandTimeout)
        AppLog.probes.debug("PersistentSession: received ${output.length} chars")
        output
    }

    fun stop() {
        AppLog.probes.info("PersistentSession: stopping...")
        session?.close()
        session = null
        isStarted = false
    }

    private suspend fun waitForReady(session: TerminalSession) {
        val deadline = monotonicSeconds() + config.startupTimeout
        val buffer = CaptureBuffer()
        val responded = HashSet<String>()
        while (monotonicSeconds() < deadline) {
            val data = session.read()
            if (data.isNotEmpty()) {
                buffer.append(data)
                val text = InteractiveRunner.utf8OrNull(buffer.toByteArray())
                if (text != null) {
                    for ((prompt, response) in config.autoResponses) {
                        if (prompt in text && prompt !in responded) {
                            AppLog.probes.debug("PersistentSession: auto-responding to '$prompt'")
                            runCatching { session.write(response.encodeToByteArray()) }
                            responded += prompt
                        }
                    }
                    if (readyMarker in text) return
                }
            }
            delay(50)
        }
        throw SessionError.TimedOut()
    }

    private suspend fun captureCommandOutput(session: TerminalSession, timeout: Double): String {
        val deadline = monotonicSeconds() + timeout
        val buffer = CaptureBuffer()
        var lastData = monotonicSeconds()
        val idleTimeout = 5.0
        val minimumContent = 500
        fun hasUsage(text: String) =
            "% used" in text || "% left" in text || "Current session" in text || "Total cost" in text

        while (monotonicSeconds() < deadline) {
            val data = session.read()
            if (data.isNotEmpty()) {
                buffer.append(data)
                lastData = monotonicSeconds()
                val text = InteractiveRunner.utf8OrNull(buffer.toByteArray())
                if (text != null && hasUsage(text)) {
                    val lines = text.split(Regex("\r\n|[\n\r\u000B\u000C\u0085  ]"))
                    if (lines.size > 5) {
                        val lastLines = lines.takeLast(5).joinToString("")
                        if (readyMarker in lastLines || "escape to cancel" in lastLines) return text
                    }
                }
            }
            val soFar = InteractiveRunner.utf8OrNull(buffer.toByteArray()).orEmpty()
            val idle = monotonicSeconds() - lastData > idleTimeout
            if (hasUsage(soFar) && idle) break
            if (buffer.size > minimumContent && idle) break
            delay(50)
        }
        return InteractiveRunner.utf8OrNull(buffer.toByteArray()) ?: throw SessionError.InvalidOutput()
    }

    private fun terminalEnvironment(): Map<String, String> {
        val environment = host.machine.environment.toMutableMap()
        environment["PATH"] = host.locator.shellPath()
        environment.getOrPut("HOME") { host.machine.homeDirectory }
        environment.getOrPut("TERM") { "xterm-256color" }
        environment.getOrPut("COLORTERM") { "truecolor" }
        environment.getOrPut("LANG") { "en_US.UTF-8" }
        environment.getOrPut("CI") { "0" }
        return environment
    }

    private companion object {
        const val TERMINAL_ROWS = 50
        const val TERMINAL_COLS = 160
    }
}
